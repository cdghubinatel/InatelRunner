# 🏃‍♂️ InatelRunner

O **InatelRunner** é um jogo de corrida infinita (endless runner) 3D vibrante, desenvolvido no motor **Godot 4.5.1** O projeto se destaca pela integração de **Visão Computacional** para controle do jogador e um sistema de geração procedural robusto.

![InatelRunner Banner](file:///c:/InatelRunner/Assets/Inatel.png)

## 🌟 Destaques do Projeto

- **🕹️ Controles:** Utilize sua webcam para controlar o personagem com movimentos do corpo.
- **🛣️ Mundo Procedural Infinito:** Estradas, calçadas, prédios e obstáculos são gerados dinamicamente.
- **🧠 Inteligência Artificial de Pose:** Integração com o modelo **YOLOv11-Pose** via **ONNX Runtime** para rastreamento de movimentos em tempo real.
- **🚀 Dificuldade Progressiva:** A velocidade do jogo e a frequência de obstáculos aumentam a cada nível alcançado.
- **⚡ Sistema de Object Pooling:** Gerenciamento eficiente de memória que reutiliza instâncias de objetos para garantir 60 FPS estáveis.
- **🏆 Ranking Persistente:** Sistema de recordes com salvamento local (`user://ranking.cfg`).

---

## 🛠️ Tecnologias e Dependências

O projeto utiliza uma arquitetura híbrida para maximizar a performance:

- **Engine:** [Godot Engine 4.5+](https://godotengine.org/) (Mono/C# Edition)
- **Lógica de Jogo:** GDScript (Sistemas de mundo, UI e jogabilidade básica).
- **Core de Visão Computacional (C#):**
    - **Microsoft.ML.OnnxRuntime:** Para inferência do modelo de Deep Learning.
    - **OpenCvSharp4:** Para captura de vídeo e pré-processamento de imagem.
    - **YOLOv11-Pose:** Modelo otimizado para detecção de pontos-chave do corpo humano.

---

## 🎮 Como Jogar

### Requisitos de Hardware
- **Webcam:** Necessária para o modo de rastreamento de movimentos.
- **GPU:** Compatível com Vulkan.

### Comandos e Gestos

| Ação | Gesto de Visão (Webcam) |
| :--- | :--- |
| **Trocar de Faixa** | Mover os braços lateralmente |
| **Pular** | Levantar braços acima dos ombros |
| **Iniciar Jogo** | `Enter` | - |

> [!TIP]
> O jogo divide a visão da câmera em 3 zonas. Mantenha seus braços centralizados para correr na faixa do meio e mova-os para os lados para desviar de carros e barreiras!

---

## 🧠 Funcionamento do HeadTracker (IA)

O componente `HeadTracker.cs` é o coração da inovação do projeto:
1. **Captura:** O frame é lido via OpenCV e espelhado para naturalidade do usuário.
2. **Thread de Inferência:** Para evitar quedas de FPS, o processamento da IA ocorre em uma thread paralela (`Task.Run`).
3. **Lógica de Decisão:**
    - Se a média da posição X dos pulsos estiver 15 pixels fora do centro dos ombros, o personagem troca de faixa.
    - Se o pulso subir acima da linha do ombro (ajustado por um limiar de 10 pixels), o pulo é acionado.

---

## 🏗️ Estrutura de Pastas

- `Assets/`: Texturas, modelos 3D (`Inatel.glb`, `Renzo.fbx`), ícones e música.
- `Resources/`:
    - `Platforms/`: Cenas de estrada, grama e plataformas aéreas.
    - `Obstacles/`: Carros (polícia, taxi, sedan), cones e barreiras.
    - `Collectibles/`: Moedas, gemas (pulo extra) e bandeiras (bônus de tempo).
- `Scenes/`: Cenas principais como `World.tscn` e `Player.tscn`.
- `Scripts/`:
    - `Global.gd`: Gerencia pontuação, níveis e recursos pré-carregados.
    - `World.gd`: O "maestro" da geração procedural e pooling.
    - `Player.gd`: Física e integração dos inputs IA/Teclado.

---

## 📦 Guia de Exportação e Build

O projeto inclui um script automatizado para garantir que todas as dependências nativas sejam incluídas no pacote final.

1. Abra o PowerShell na raiz do projeto.
2. Execute o comando:
   ```powershell
   ./Exportar_InatelRunner.ps1
   ```
*Este script automatiza a compilação .NET, exportação do Godot e a cópia das DLLs do ONNX/OpenCV para a pasta `builds/export_final`.*

---

## 📝 Créditos e Desenvolvimento

Desenvolvido com foco em demonstrar a integração de IA moderna em motores de jogos.
- **Desenvolvedor:** Lucas Caixeta Generoso - CDGHUB Inatel
- **Modelo de IA:** Ultralytics YOLOv11
- **Assets 3D:** Kenney Assets / Custom models
