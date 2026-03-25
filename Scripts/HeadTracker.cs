using Godot;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using System;
using System.Linq;
using System.Collections.Generic;
using System.IO; // Adicione esta linha

public partial class HeadTracker : Node
{
	private InferenceSession session;
	private CameraTexture cameraTexture;
	private CameraFeed feed;

	[Export]
	public TextureRect CameraPreview; 

	public float NosePositionX { get; private set; } = 0.5f;

	private const int ModelInputWidth = 640;
	private const int ModelInputHeight = 640;
	
	private int frameCounter = 0;
	private const int ProcessEveryNFrames = 2; 
	
	public float ArmCenterPositionX { get; private set; } = 0.5f;
	public bool ShouldJump { get; private set; } = false;
	
	public override void _Ready()
	{
		string modelName = "yolo11n-pose.onnx";
		string resPath = "res://" + modelName;
		string userPath = OS.GetUserDataDir() + "/" + modelName;
		if (!System.IO.File.Exists(userPath))
		{
			using var file = Godot.FileAccess.Open(resPath, Godot.FileAccess.ModeFlags.Read);
			if (file != null)
			{
				byte[] buffer = file.GetBuffer((long)file.GetLength());
				System.IO.File.WriteAllBytes(userPath, buffer);
				GD.Print("Modelo IA copiado para a pasta do usuário.");
			}
		}
		// 1. Carregar IA
		try 
		{
			session = new InferenceSession(userPath);
			GD.Print("Modelo IA Carregado!");
		}
		catch (Exception e)
		{
			GD.PrintErr("Erro ao carregar modelo ONNX: " + e.Message);
		}

		// 2. Iniciar Webcam
		if (CameraServer.GetFeedCount() > 0)
		{
			feed = CameraServer.GetFeed(0);
			
			var formats = feed.GetFormats();
			if (formats.Count > 0)
			{
				var parameters = (Godot.Collections.Dictionary)formats[0];
				feed.SetFormat(0, parameters);
			}

			feed.FeedIsActive = true; 
			GD.Print($"Webcam ativada: {feed.GetName()}");

			// Criar a textura
			cameraTexture = new CameraTexture();
			cameraTexture.CameraFeedId = feed.GetId();

			if (CameraPreview != null)
			{
				CameraPreview.Texture = cameraTexture;
			}
		}
		else
		{
			GD.PrintErr("Nenhuma webcam detectada!");
		}
	}

	public override void _Process(double delta)
	{
		if (cameraTexture == null || session == null) return;

		frameCounter++;
		if (frameCounter % ProcessEveryNFrames != 0) return;

		Image img = cameraTexture.GetImage();
		
		if (img == null || img.IsEmpty()) return;

		// Copiar e redimensionar para a IA
		Image imgForAi = (Image)img.Duplicate();
		imgForAi.Resize(ModelInputWidth, ModelInputHeight); 
		
		var inputTensor = ConvertGodotImageToTensor(imgForAi);

		try 
		{
			var inputs = new NamedOnnxValue[] { NamedOnnxValue.CreateFromTensor("images", inputTensor) };
			
			using (var results = session.Run(inputs))
			{
				var output = results.First().AsTensor<float>();
				ProcessBodyPose(output);
			}
		}
		catch (Exception e) { 
			GD.Print("Erro na inferência: " + e.Message);
		}
	}

	// (Funções auxiliares mantêm-se iguais)
	private DenseTensor<float> ConvertGodotImageToTensor(Image image)
	{
		var tensor = new DenseTensor<float>(new[] { 1, 3, ModelInputHeight, ModelInputWidth });
		byte[] data = image.GetData();
		
		int channels = (image.GetFormat() == Image.Format.Rgba8) ? 4 : 3;
		int pixelCount = ModelInputWidth * ModelInputHeight;
		
		if (data.Length < pixelCount * channels) return tensor;

		for (int i = 0; i < pixelCount; i++)
		{
			int dataIndex = i * channels;
			
			float r = data[dataIndex] / 255.0f;
			float g = data[dataIndex + 1] / 255.0f;
			float b = data[dataIndex + 2] / 255.0f;

			int x = i % ModelInputWidth;
			int y = i / ModelInputWidth;

			tensor[0, 0, y, x] = r;
			tensor[0, 1, y, x] = g;
			tensor[0, 2, y, x] = b;
		}

		return tensor;
	}

	private void ProcessBodyPose(Tensor<float> output)
	{
		int anchors = output.Dimensions[2]; 
		float maxScore = 0f;
		int bestAnchorIndex = -1;

		for (int i = 0; i < anchors; i++)
		{
			float score = output[0, 4, i]; // Score de confiança da pessoa
			if (score > maxScore)
			{
				maxScore = score;
				bestAnchorIndex = i;
			}
		}

		if (bestAnchorIndex != -1 && maxScore > 0.5f)
		{
			// 1. MOVIMENTO LATERAL (Média dos pulsos ou ombros)
			// Keypoints no YOLO Pose começam no índice 5 (x,y,conf)
			// Pulso Esquerdo: 9, Pulso Direito: 10
			float wristLX = output[0, 5 + (9 * 3), bestAnchorIndex];
			float wristRX = output[0, 5 + (10 * 3), bestAnchorIndex];
			float avgWristX = (wristLX + wristRX) / 2.0f;

			float normalizedX = avgWristX / ModelInputWidth;
			ArmCenterPositionX = 1.0f - Math.Clamp(normalizedX, 0f, 1f);

			// 2. LÓGICA DO PULO (Braços acima da cabeça/ombros)
			// Se a posição Y do pulso (ponto 9/10) for menor que a do ombro (ponto 5/6)
			// Nota: No 2D do computador, Y=0 é o topo. Então pulso < ombro significa braço levantado.
			float shoulderLY = output[0, 5 + (5 * 3) + 1, bestAnchorIndex];
			float wristLY = output[0, 5 + (9 * 3) + 1, bestAnchorIndex];

			// Se o pulso estiver consideravelmente acima do ombro
			ShouldJump = wristLY < (shoulderLY - 30); 
		}
}

	public override void _ExitTree()
	{
		session?.Dispose();
		if (feed != null) feed.FeedIsActive = false;
	}
}
