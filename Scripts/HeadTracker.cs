using Godot;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using System;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.IO;
using OpenCvSharp;

public partial class HeadTracker : Node
{
	private InferenceSession session;
	private VideoCapture capture;
	private Mat frame;
	private Godot.ImageTexture imageTexture;

	[Export]
	public TextureRect CameraPreview; 

	public float NosePositionX { get; private set; } = 0.5f;

	private const int ModelInputWidth = 640;
	private const int ModelInputHeight = 640;
	
	private bool isInferencing = false;
	private double timeSinceLastInference = 0.0;
	private const double InferenceCooldown = 0.066; // Limita a IA para ~15 FPS
	
	public float ArmCenterPositionX { get; private set; } = 0.5f;
	public bool ShouldJump { get; private set; } = false;
	
	public override void _Ready()
	{
		// 1. Iniciar OpenCV VideoCapture
		GD.Print("Iniciando OpenCV...");
		capture = new VideoCapture(0, VideoCaptureAPIs.ANY);
		if (capture.IsOpened())
		{
			GD.Print("OpenCV Câmera ativada!");
			frame = new Mat();
			imageTexture = new Godot.ImageTexture();
		}
		else
		{
			GD.PrintErr("OpenCV Falhou ao abrir câmera.");
			capture.Dispose();
			capture = null;
		}

		// 2. Carregar IA DEPOIS
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

		try 
		{
			using (var options = new SessionOptions())
			{
				options.InterOpNumThreads = 1;
				options.IntraOpNumThreads = 1;
				options.GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL;
				session = new InferenceSession(userPath, options);
			}
			GD.Print("Modelo IA Carregado com Otimizações de CPU!");
		}
		catch (Exception e)
		{
			GD.PrintErr("Erro ao carregar modelo ONNX: " + e.Message);
			if (e.InnerException != null) GD.PrintErr("Inner: " + e.InnerException.Message);
		}
	}

	public override void _Process(double delta)
	{
		if (capture == null || !capture.IsOpened() || session == null) return;

		// Lê o frame
		capture.Read(frame);
		if (frame.Empty()) return;

		// Espelha a imagem UMA VEZ para a tela e para a IA (Custo zero de performance na duplicação)
		Cv2.Flip(frame, frame, FlipMode.Y);

		// OpenCV retorna BGR, precisamos de RGB para o Godot
		Cv2.CvtColor(frame, frame, ColorConversionCodes.BGR2RGB);

		// Copia os dados do Mat para um array de bytes gerenciado
		int bufferSize = (int)(frame.Total() * frame.ElemSize());
		byte[] imgData = new byte[bufferSize];
		System.Runtime.InteropServices.Marshal.Copy(frame.Data, imgData, 0, bufferSize);
		
		// Cria a imagem do Godot
		Godot.Image godotImage = Godot.Image.CreateFromData(frame.Width, frame.Height, false, Godot.Image.Format.Rgb8, imgData);
		
		// Atualiza o preview visual na UI
		if (CameraPreview != null && godotImage != null)
		{
			var newTexture = Godot.ImageTexture.CreateFromImage(godotImage);
			CameraPreview.Texture = newTexture;
		}

		timeSinceLastInference += delta;
		if (timeSinceLastInference < InferenceCooldown) return;
		
		if (isInferencing) return;
		
		timeSinceLastInference = 0.0;
		isInferencing = true;
		
		// Passa a mesma imagem espelhada para a IA
		Godot.Image imgForAi = (Godot.Image)godotImage.Duplicate();

		Task.Run(() => {
			try 
			{
				// Movemos o processamento pesado (Resize) para a thread secundária!
				imgForAi.Resize(ModelInputWidth, ModelInputHeight); 
				byte[] resizedData = imgForAi.GetData();
				int channels = 3; // RGB sempre tem 3 canais
				imgForAi.Dispose();

				var inputTensor = ConvertGodotImageToTensor(resizedData, channels);
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

			// Como espelhamos a imagem, invertemos o resultado da matemática para o tracking ficar correto!
			if (offset > offsetThreshold) {
				ArmCenterPositionX = 0.8f; // Força target_lane = 0 (Esquerda) no Player.gd
			} else if (offset < -offsetThreshold) {
				ArmCenterPositionX = 0.2f; // Força target_lane = 2 (Direita) no Player.gd
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
		if (capture != null)
		{
			capture.Release();
			capture.Dispose();
		}
		if (frame != null) frame.Dispose();
	}
}
