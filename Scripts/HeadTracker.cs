using Godot;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using System;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.IO;
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
	
	private bool isInferencing = false;
	
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
		if (isInferencing) return;

		Image img = cameraTexture.GetImage();
		if (img == null || img.IsEmpty()) return;

		Image imgForAi = (Image)img.Duplicate();
		imgForAi.Resize(ModelInputWidth, ModelInputHeight); 
		byte[] imgData = imgForAi.GetData();
		int channels = (imgForAi.GetFormat() == Image.Format.Rgba8) ? 4 : 3;

		imgForAi.Dispose();
		img.Dispose();

		isInferencing = true;
		
		Task.Run(() => {
			try 
			{
				var inputTensor = ConvertGodotImageToTensor(imgData, channels);
				var inputs = new NamedOnnxValue[] { NamedOnnxValue.CreateFromTensor("images", inputTensor) };
				
				using (var results = session.Run(inputs))
				{
					var output = results.First().AsTensor<float>();
					ProcessBodyPose(output);
				}
			}
			catch (Exception e) 
			{ 
				GD.Print("Erro na inferência: " + e.Message);
			}
			finally 
			{
				isInferencing = false;
			}
		});
	}

	private DenseTensor<float> ConvertGodotImageToTensor(byte[] data, int channels)
	{
		int pixelCount = ModelInputWidth * ModelInputHeight;
		float[] floatArray = new float[3 * pixelCount];
		
		if (data.Length < pixelCount * channels) 
		{
			return new DenseTensor<float>(new[] { 1, 3, ModelInputHeight, ModelInputWidth });
		}

		int gOffset = pixelCount;
		int bOffset = 2 * pixelCount;
		float inv255 = 1.0f / 255.0f;

		for (int i = 0; i < pixelCount; i++)
		{
			int dataIndex = i * channels;
			floatArray[i] = data[dataIndex] * inv255;
			floatArray[gOffset + i] = data[dataIndex + 1] * inv255;
			floatArray[bOffset + i] = data[dataIndex + 2] * inv255;
		}

		return new DenseTensor<float>(floatArray, new[] { 1, 3, ModelInputHeight, ModelInputWidth });
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
			// 1. MOVIMENTO LATERAL (Braços relativos ao centro dos ombros)
			float shoulderLX = output[0, 5 + (5 * 3), bestAnchorIndex];
			float shoulderRX = output[0, 5 + (6 * 3), bestAnchorIndex];
			float shoulderCenter = (shoulderLX + shoulderRX) / 2.0f;

			float wristLX = output[0, 5 + (9 * 3), bestAnchorIndex];
			float wristRX = output[0, 5 + (10 * 3), bestAnchorIndex];
			float avgWristX = (wristLX + wristRX) / 2.0f;

			// Desvio horizontal em pixels
			float offset = avgWristX - shoulderCenter;
			
			// Margem para trocar de faixa (reduzido para dar resposta instantânea)
			float offsetThreshold = 15.0f; 

			if (offset > offsetThreshold) {
				ArmCenterPositionX = 0.2f; // Força target_lane = 2 (Direita) no Player.gd
			} else if (offset < -offsetThreshold) {
				ArmCenterPositionX = 0.8f; // Força target_lane = 0 (Esquerda) no Player.gd
			} else {
				ArmCenterPositionX = 0.5f; // Centro
			}

			// 2. LÓGICA DO PULO (Braços acima da cabeça/ombros)
			float shoulderLY = output[0, 5 + (5 * 3) + 1, bestAnchorIndex];
			float wristLY = output[0, 5 + (9 * 3) + 1, bestAnchorIndex];

			// Menor limiar (-10 invés de -30) faz o pulo ler gestos ágeis
			ShouldJump = wristLY < (shoulderLY - 10);  
		}
}

	public override void _ExitTree()
	{
		session?.Dispose();
		if (feed != null) feed.FeedIsActive = false;
	}
}
