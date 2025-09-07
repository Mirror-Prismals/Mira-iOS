import UIKit
import SceneKit
import Speech
import AVFoundation
import NaturalLanguage

// MARK: - Data Models
struct ColorTheme {
    let name: String
    let displayColor: UIColor
    let price: Int // MODIFIED: Renamed from chatsRequired for clarity
    var isUnlocked: Bool
}

struct ChatMessage: Codable {
    enum Sender: Codable {
        case user
        case assistant
    }
    let id: UUID
    let text: String
    let sender: Sender
    let timestamp: Date
}

// MARK: - Chat History Persistence Manager
class ChatHistoryManager {
    static let shared = ChatHistoryManager()
    private let fileURL: URL

    private init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = documentsDirectory.appendingPathComponent("chatHistory.json")
    }

    func save(message: ChatMessage) {
        var history = loadHistory()
        history.append(message)
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save chat history: \(error)")
        }
    }

    func loadHistory() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let history = try JSONDecoder().decode([ChatMessage].self, from: data)
            return history
        } catch {
            print("Failed to decode chat history: \(error)")
            return []
        }
    }

    func clearHistory() {
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("Chat history cleared.")
        } catch {
            print("Failed to clear chat history: \(error)")
        }
    }
}

// MARK: - Game View Controller
class GameViewController: UIViewController, SCNSceneRendererDelegate, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {

    // MARK: - SceneKit & UI
    var scnView: SCNView!
    var sphereNode: SCNNode!
    var directionalLightNode: SCNNode!
    var omniLightNode: SCNNode!
    var secondOmniLightNode: SCNNode! // --- ADDED ---: Declaration for the new light
    var floorNode: SCNNode!
    var textNode: SCNNode!
    var lockTextNode: SCNNode!
    
    var chatHistoryView: UIView!
    var chatHistoryViewTopConstraint: NSLayoutConstraint!
    var chatHistoryTableView: UITableView!
    var settingsButton: UIButton!
    var settingsView: UIView!
    var settingsViewTopConstraint: NSLayoutConstraint!
    var currencyLabel: UILabel!
    // --- NEW: UI for custom purchase and loading screens ---
    var purchaseView: UIView!
    var purchaseViewTopConstraint: NSLayoutConstraint!
    var purchaseThemeNameLabel: UILabel!
    var purchaseThemePriceLabel: UILabel!
    var loadingView: UIView!
    
    
    // MARK: - Speech & Audio
    let speechRecognizer = SFSpeechRecognizer()
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    let audioEngine = AVAudioEngine()
    let speechSynthesizer = AVSpeechSynthesizer()
    var isRecording: Bool = false
    var audioAmplitude: Float = 0.0
    var displayLink: CADisplayLink?
    
    // MARK: - Assistant Logic
    var isAssistantSpeaking: Bool = false
    var currentSpeechRange: NSRange = NSRange(location: 0, length: 0)
    var aiResponseGenerator: ((String) -> String)?
    private var chatMessages: [ChatMessage] = []
    var markovChainGenerator = MarkovChainGenerator()


    // MARK: - Color Themes
    let tangerineColor = UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0)
    let aquaColor = UIColor(red: 0.0, green: 0.81, blue: 0.82, alpha: 1.0)
    let indigoColor = UIColor(red: 0.29, green: 0.0, blue: 0.51, alpha: 1.0)
    let limeColor = UIColor(red: 0.59, green: 0.99, blue: 0.61, alpha: 1.0)
    let blueColor = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
    let redColor = UIColor.red
    let yellowColor = UIColor.yellow
    
    let tangerineAquaPlaceholder = UIColor(white: 0.0, alpha: 0.1)
    let indigoLimePlaceholder = UIColor(white: 0.0, alpha: 0.2)
    let indigoRedPlaceholder = UIColor(white: 0.0, alpha: 0.3)
    let indigoYellowPlaceholder = UIColor(white: 0.0, alpha: 0.4)
    let limeOrangePlaceholder = UIColor(white: 0.0, alpha: 0.5)
    let blueRedPlaceholder = UIColor(white: 0.0, alpha: 0.6)
    let triColorPlaceholder = UIColor(white: 0.0, alpha: 0.7)

    private lazy var themes: [ColorTheme] = [
        ColorTheme(name: "Indigo", displayColor: indigoColor, price: 600, isUnlocked: false),
        ColorTheme(name: "Pastel Lime", displayColor: limeColor, price: 10, isUnlocked: false),
        ColorTheme(name: "Tangerine", displayColor: tangerineColor, price: 20, isUnlocked: false),
        ColorTheme(name: "Aqua", displayColor: aquaColor, price: 30, isUnlocked: false),
        ColorTheme(name: "Blue", displayColor: blueColor, price: 40, isUnlocked: false),
        ColorTheme(name: "Yellow", displayColor: yellowColor, price: 50, isUnlocked: false),
        ColorTheme(name: "Red", displayColor: redColor, price: 120, isUnlocked: false),
        ColorTheme(name: "Black", displayColor: .black, price: 700, isUnlocked: false),
        ColorTheme(name: "White", displayColor: .white, price: 800, isUnlocked: false),
        ColorTheme(name: "Tangerine Aqua", displayColor: tangerineAquaPlaceholder, price: 1000, isUnlocked: false),
        ColorTheme(name: "Indigo Lime", displayColor: indigoLimePlaceholder, price: 0, isUnlocked: true),
        ColorTheme(name: "Indigo Red", displayColor: indigoRedPlaceholder, price: 1400, isUnlocked: false),
        ColorTheme(name: "Blue Red", displayColor: blueRedPlaceholder, price: 1600, isUnlocked: false),
        ColorTheme(name: "Tri-Color", displayColor: triColorPlaceholder, price: 2000, isUnlocked: false)
    ]

    private var currentThemeIndex: Int = 0
    private var tapAmplitude: Float = 0.0
    
    // MARK: - Persistence & Currency
    private let themeKey = "lastThemeIndex"
    private let unlockedThemesKey = "unlockedThemeNames"
    private let currencyKey = "userCurrency"
    private var userCurrency: Int = 0
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        loadGameData()
        chatMessages = ChatHistoryManager.shared.loadHistory()
        setupScene()
        setupChatHistoryUI()
        setupSettingsUI()
        // --- NEW: Setup for new UI elements ---
        setupPurchaseUI()
        setupLoadingUI()
        
        setupSpeechRecognizer()
        setupDisplayLink()
        setupAudioEngine()
        
        trainAI()
        aiResponseGenerator = { [weak self] input in
            guard let self = self else { return "I'm not sure what to say." }
            return self.markovChainGenerator.generateResponse(for: input)
        }
    }
    
    // MARK: - AI Training
    func trainAI() {
        let corpus = chatMessages.map { $0.text }.joined(separator: "\n")
        markovChainGenerator.train(with: corpus)
        print("AI model trained on corpus of \(corpus.count) characters.")
    }
    
    // MARK: - Setup
    func setupScene() {
        let scene = SCNScene()
        if let view = self.view as? SCNView { scnView = view }
        else {
            scnView = SCNView(frame: self.view.bounds)
            self.view.addSubview(scnView)
            scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        scnView.scene = scene
        scnView.allowsCameraControl = false
        scnView.rendersContinuously = true
        scnView.autoenablesDefaultLighting = false
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 10)
        scene.rootNode.addChildNode(cameraNode)
        
        // --- DELETED ---: The static ambient light is no longer needed.
        // let ambientLightNode = SCNNode()
        // ambientLightNode.light = SCNLight()
        // ambientLightNode.light!.type = .ambient
        // ambientLightNode.light!.color = UIColor.darkGray
        // scene.rootNode.addChildNode(ambientLightNode)
        
        directionalLightNode = SCNNode()
        directionalLightNode.light = SCNLight()
        directionalLightNode.light!.type = .directional
        directionalLightNode.light!.color = UIColor.white
        directionalLightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        directionalLightNode.light!.castsShadow = true
        scene.rootNode.addChildNode(directionalLightNode)
        
        omniLightNode = SCNNode()
        omniLightNode.light = SCNLight()
        omniLightNode.light!.type = .omni
        omniLightNode.position = SCNVector3(x: -5, y: 5, z: 5)
        scene.rootNode.addChildNode(omniLightNode)
        
        // --- ADDED ---: Setup for the second moving omni light.
        // It has a distinct cool color to contrast with the theme-based light.
        secondOmniLightNode = SCNNode()
        secondOmniLightNode.light = SCNLight()
        secondOmniLightNode.light!.type = .omni
        secondOmniLightNode.light!.color = UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0) // A cool light blue
        secondOmniLightNode.light!.intensity = 1200 // Omni lights need intensity to be visible
        secondOmniLightNode.position = SCNVector3(x: 5, y: 5, z: -5)
        scene.rootNode.addChildNode(secondOmniLightNode)
        
        scene.lightingEnvironment.contents = UIColor.gray
        scene.lightingEnvironment.intensity = 1.5
        let sphereGeometry = SCNSphere(radius: 1.5)
        sphereGeometry.firstMaterial?.lightingModel = .physicallyBased
        sphereGeometry.firstMaterial?.metalness.contents = 0.9
        sphereGeometry.firstMaterial?.roughness.contents = 0.2
        sphereNode = SCNNode(geometry: sphereGeometry)
        sphereNode.position = SCNVector3(x: 0, y: 0, z: 0)
        sphereNode.castsShadow = true
        scene.rootNode.addChildNode(sphereNode)
        let textGeometry = SCNText(string: "", extrusionDepth: 0.1)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        textGeometry.font = UIFont.systemFont(ofSize: 0.5)
        textNode = SCNNode(geometry: textGeometry)
        textNode.position = SCNVector3(x: 0, y: 3.0, z: 0)
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)
        textNode.opacity = 0.0
        scene.rootNode.addChildNode(textNode)
        
        let lockTextGeometry = SCNText(string: "", extrusionDepth: 0.1)
        lockTextGeometry.font = UIFont.systemFont(ofSize: 0.8, weight: .heavy)
        lockTextGeometry.firstMaterial?.diffuse.contents = UIColor.white
        lockTextNode = SCNNode(geometry: lockTextGeometry)
        lockTextNode.position = SCNVector3(x: 0, y: 0, z: 1)
        lockTextNode.opacity = 0.0
        scene.rootNode.addChildNode(lockTextNode)
        
        let floorGeometry = SCNPlane(width: 20, height: 20)
        floorGeometry.firstMaterial?.lightingModel = .physicallyBased
        floorGeometry.firstMaterial?.metalness.contents = 0.0
        floorGeometry.firstMaterial?.roughness.contents = 0.8
        floorNode = SCNNode(geometry: floorGeometry)
        floorNode.eulerAngles = SCNVector3Make(Float(-Double.pi / 2), 0, 0)
        floorNode.position = SCNVector3(x: 0, y: -2, z: 0)
        scene.rootNode.addChildNode(floorNode)
        
        updateTheme()

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.1
        scnView.addGestureRecognizer(longPressGesture)
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        scnView.addGestureRecognizer(swipeRight)
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        scnView.addGestureRecognizer(swipeLeft)
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeUp.direction = .up
        scnView.addGestureRecognizer(swipeUp)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
    }
    
    func setupChatHistoryUI() {
        chatHistoryView = UIView()
        chatHistoryView.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        chatHistoryView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(chatHistoryView, aboveSubview: scnView)
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Chat History"
        titleLabel.textColor = .black
        titleLabel.font = UIFont.systemFont(ofSize: 34, weight: .bold)
        chatHistoryView.addSubview(titleLabel)
        
        settingsButton = UIButton(type: .system)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        settingsButton.setImage(UIImage(systemName: "gearshape.fill", withConfiguration: config), for: .normal)
        settingsButton.tintColor = .darkGray
        settingsButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        chatHistoryView.addSubview(settingsButton)

        chatHistoryTableView = UITableView()
        chatHistoryTableView.translatesAutoresizingMaskIntoConstraints = false
        chatHistoryTableView.dataSource = self
        chatHistoryTableView.delegate = self
        chatHistoryTableView.register(ChatBubbleCell.self, forCellReuseIdentifier: "ChatBubbleCell")
        chatHistoryTableView.separatorStyle = .none
        chatHistoryTableView.backgroundColor = .clear
        chatHistoryTableView.transform = CGAffineTransform(scaleX: 1, y: -1)
        chatHistoryView.addSubview(chatHistoryTableView)
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(hideChatHistory))
        swipeDown.direction = .down
        chatHistoryView.addGestureRecognizer(swipeDown)

        chatHistoryViewTopConstraint = chatHistoryView.topAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([
            chatHistoryView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatHistoryView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatHistoryView.heightAnchor.constraint(equalTo: view.heightAnchor),
            chatHistoryViewTopConstraint,
            
            titleLabel.centerXAnchor.constraint(equalTo: chatHistoryView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: chatHistoryView.safeAreaLayoutGuide.topAnchor, constant: 20),
            
            settingsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: chatHistoryView.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            
            chatHistoryTableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            chatHistoryTableView.leadingAnchor.constraint(equalTo: chatHistoryView.leadingAnchor),
            chatHistoryTableView.trailingAnchor.constraint(equalTo: chatHistoryView.trailingAnchor),
            chatHistoryTableView.bottomAnchor.constraint(equalTo: chatHistoryView.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    func setupSettingsUI() {
        settingsView = UIView()
        settingsView.backgroundColor = .white
        settingsView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(settingsView, aboveSubview: chatHistoryView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Settings"
        titleLabel.textColor = .black
        titleLabel.font = UIFont.systemFont(ofSize: 34, weight: .bold)
        settingsView.addSubview(titleLabel)
        
        let currencyContainer = UIView()
        currencyContainer.translatesAutoresizingMaskIntoConstraints = false
        currencyContainer.backgroundColor = UIColor.systemGroupedBackground
        currencyContainer.layer.cornerRadius = 12
        settingsView.addSubview(currencyContainer)
        
        let currencyTitleLabel = UILabel()
        currencyTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        currencyTitleLabel.text = "Your Balance"
        currencyTitleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        currencyTitleLabel.textColor = .darkGray
        currencyContainer.addSubview(currencyTitleLabel)
        
        currencyLabel = UILabel()
        currencyLabel.translatesAutoresizingMaskIntoConstraints = false
        currencyLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        currencyLabel.textColor = .black
        currencyContainer.addSubview(currencyLabel)

        let resetProgressButton = createSettingsButton(iconName: "trash", labelText: "Reset Unlock Progress", tintColor: .red, action: #selector(resetProgressTapped))
        let resetHistoryButton = createSettingsButton(iconName: "trash", labelText: "Reset Conversation History", tintColor: .systemBlue, action: #selector(resetHistoryTapped))
        let exportCorpusButton = createSettingsButton(iconName: "square.and.arrow.up", labelText: "Export Corpus Data", tintColor: .systemGreen, action: #selector(exportCorpusTapped))

        let stackView = UIStackView(arrangedSubviews: [resetProgressButton, resetHistoryButton, exportCorpusButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 15
        settingsView.addSubview(stackView)
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(hideSettings))
        swipeDown.direction = .down
        settingsView.addGestureRecognizer(swipeDown)
        
        settingsViewTopConstraint = settingsView.topAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            settingsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            settingsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            settingsView.heightAnchor.constraint(equalTo: view.heightAnchor),
            settingsViewTopConstraint,
            
            titleLabel.centerXAnchor.constraint(equalTo: settingsView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: settingsView.safeAreaLayoutGuide.topAnchor, constant: 40),
            
            currencyContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 30),
            currencyContainer.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            currencyContainer.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            currencyContainer.heightAnchor.constraint(equalToConstant: 80),
            
            currencyTitleLabel.topAnchor.constraint(equalTo: currencyContainer.topAnchor, constant: 15),
            currencyTitleLabel.leadingAnchor.constraint(equalTo: currencyContainer.leadingAnchor, constant: 20),
            
            currencyLabel.topAnchor.constraint(equalTo: currencyTitleLabel.bottomAnchor, constant: 2),
            currencyLabel.leadingAnchor.constraint(equalTo: currencyContainer.leadingAnchor, constant: 20),
            
            stackView.topAnchor.constraint(equalTo: currencyContainer.bottomAnchor, constant: 40),
            stackView.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
        ])
    }
    
    // --- NEW: Setup for the custom purchase UI ---
    func setupPurchaseUI() {
        purchaseView = UIView()
        purchaseView.backgroundColor = .white
        purchaseView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(purchaseView, aboveSubview: settingsView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Confirm Purchase"
        titleLabel.textColor = .black
        titleLabel.font = UIFont.systemFont(ofSize: 34, weight: .bold)
        purchaseView.addSubview(titleLabel)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemGroupedBackground
        container.layer.cornerRadius = 20
        purchaseView.addSubview(container)
        
        purchaseThemeNameLabel = UILabel()
        purchaseThemeNameLabel.translatesAutoresizingMaskIntoConstraints = false
        purchaseThemeNameLabel.font = UIFont.systemFont(ofSize: 28, weight: .semibold)
        purchaseThemeNameLabel.textAlignment = .center
        container.addSubview(purchaseThemeNameLabel)
        
        purchaseThemePriceLabel = UILabel()
        purchaseThemePriceLabel.translatesAutoresizingMaskIntoConstraints = false
        purchaseThemePriceLabel.font = UIFont.systemFont(ofSize: 42, weight: .bold)
        purchaseThemePriceLabel.textAlignment = .center
        container.addSubview(purchaseThemePriceLabel)

        let cancelButton = createPurchaseButton(title: "Cancel", backgroundColor: .systemGray5, titleColor: .darkGray, action: #selector(cancelPurchase))
        let unlockButton = createPurchaseButton(title: "Unlock", backgroundColor: .systemGreen, titleColor: .white, action: #selector(confirmPurchase))

        let buttonStack = UIStackView(arrangedSubviews: [cancelButton, unlockButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 15
        buttonStack.distribution = .fillEqually
        purchaseView.addSubview(buttonStack)

        purchaseViewTopConstraint = purchaseView.topAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            purchaseView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            purchaseView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            purchaseView.heightAnchor.constraint(equalTo: view.heightAnchor),
            purchaseViewTopConstraint,
            
            titleLabel.centerXAnchor.constraint(equalTo: purchaseView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: purchaseView.safeAreaLayoutGuide.topAnchor, constant: 60),

            container.centerYAnchor.constraint(equalTo: purchaseView.centerYAnchor, constant: -80),
            container.leadingAnchor.constraint(equalTo: purchaseView.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: purchaseView.trailingAnchor, constant: -20),
            container.heightAnchor.constraint(equalToConstant: 200),
            
            purchaseThemeNameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            purchaseThemeNameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            purchaseThemeNameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            
            purchaseThemePriceLabel.topAnchor.constraint(equalTo: purchaseThemeNameLabel.bottomAnchor, constant: 10),
            purchaseThemePriceLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            purchaseThemePriceLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            
            buttonStack.bottomAnchor.constraint(equalTo: purchaseView.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            buttonStack.leadingAnchor.constraint(equalTo: purchaseView.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: purchaseView.trailingAnchor, constant: -20),
            buttonStack.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    // --- NEW: Setup for the loading indicator UI ---
    func setupLoadingUI() {
        loadingView = UIView()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        loadingView.alpha = 0 // Start hidden
        view.addSubview(loadingView)

        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .white
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        loadingView.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: view.topAnchor),
            loadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor)
        ])
    }
    
    func createSettingsButton(iconName: String, labelText: String, tintColor: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: iconName)
        config.title = labelText
        config.baseBackgroundColor = tintColor.withAlphaComponent(0.1)
        config.baseForegroundColor = tintColor
        config.imagePadding = 10
        config.cornerStyle = .medium
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }
    
    func createPurchaseButton(title: String, backgroundColor: UIColor, titleColor: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.backgroundColor = backgroundColor
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        button.layer.cornerRadius = 15
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - UI Presentation
    @objc func showChatHistory() {
        chatHistoryTableView.reloadData()
        
        if !chatMessages.isEmpty {
            DispatchQueue.main.async {
                let firstIndexPath = IndexPath(row: 0, section: 0)
                self.chatHistoryTableView.scrollToRow(at: firstIndexPath, at: .top, animated: false)
            }
        }
        
        chatHistoryViewTopConstraint.constant = -view.frame.height
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }
    
    @objc func hideChatHistory() {
        chatHistoryViewTopConstraint.constant = 0
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn, animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

    @objc func showSettings() {
        currencyLabel.text = "💰 \(userCurrency)"
        settingsViewTopConstraint.constant = -view.frame.height
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }
    
    @objc func hideSettings() {
        settingsViewTopConstraint.constant = 0
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn, animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }
    
    // --- NEW: Methods to show/hide the custom purchase screen ---
    func showPurchaseScreen() {
        let theme = themes[currentThemeIndex]
        purchaseThemeNameLabel.text = theme.name
        purchaseThemePriceLabel.text = "💰 \(theme.price)"
        
        purchaseViewTopConstraint.constant = -view.frame.height
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

    func hidePurchaseScreen() {
        purchaseViewTopConstraint.constant = 0
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn, animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }
    
    // --- NEW: Methods to show/hide the loading indicator ---
    func showLoadingIndicator() {
        UIView.animate(withDuration: 0.2) {
            self.loadingView.alpha = 1.0
        }
    }

    func hideLoadingIndicator() {
        UIView.animate(withDuration: 0.2) {
            self.loadingView.alpha = 0.0
        }
    }
    
    // MARK: - Actions
    @objc func resetProgressTapped() {
        let alert = UIAlertController(title: "Reset Progress?", message: "Are you sure you want to re-lock all themes and reset your currency? This cannot be undone.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive, handler: { _ in
            self.resetGameProgress()
        }))
        present(alert, animated: true)
    }
    
    @objc func resetHistoryTapped() {
        let alert = UIAlertController(title: "Reset History?", message: "Are you sure you want to permanently delete your entire conversation history?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive, handler: { _ in
            self.resetConversationHistory()
        }))
        present(alert, animated: true)
    }
    
    @objc func exportCorpusTapped() {
        // --- MODIFIED: Show loading indicator and perform file writing on a background thread ---
        showLoadingIndicator()

        // Estimate loading time based on number of chats (e.g., 0.0001 seconds per chat)
        let estimatedTime = Double(chatMessages.count) * 0.0001
        let minDisplayTime = 0.5 // Show loading for at least half a second
        let delay = max(estimatedTime, minDisplayTime)

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            let corpus = self.chatMessages.map { $0.text }.joined(separator: "\n")
            
            guard !corpus.isEmpty else {
                DispatchQueue.main.async {
                    self.hideLoadingIndicator()
                    let alert = UIAlertController(title: "Nothing to Export", message: "Your chat history is empty.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    self.present(alert, animated: true)
                }
                return
            }

            let fileName = "corpus.txt"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try corpus.write(to: tempURL, atomically: true, encoding: .utf8)
                
                // Switch back to the main thread to present the UI
                DispatchQueue.main.async {
                    self.hideLoadingIndicator()
                    let activityViewController = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                    if let popoverController = activityViewController.popoverPresentationController {
                        popoverController.sourceView = self.view
                        popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                        popoverController.permittedArrowDirections = []
                    }
                    self.present(activityViewController, animated: true, completion: nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.hideLoadingIndicator()
                    print("Failed to create temporary corpus file: \(error)")
                }
            }
        }
    }
    
    // --- NEW: Actions for the custom purchase screen ---
    @objc func confirmPurchase() {
        let theme = themes[currentThemeIndex]
        userCurrency -= theme.price
        themes[currentThemeIndex].isUnlocked = true
        saveGameData()
        updateTheme()
        hidePurchaseScreen()
    }

    @objc func cancelPurchase() {
        hidePurchaseScreen()
    }
    
    func resetGameProgress() {
        print("--- PROGRESS RESET ---")
        userCurrency = 0
        var defaultIndex = 0
        for i in 0..<themes.count {
            themes[i].isUnlocked = (themes[i].price == 0)
            if themes[i].isUnlocked {
                defaultIndex = i
            }
        }
        currentThemeIndex = defaultIndex
        saveGameData()
        updateTheme()
        hideSettings()
    }
    
    func resetConversationHistory() {
        ChatHistoryManager.shared.clearHistory()
        chatMessages.removeAll()
        chatHistoryTableView.reloadData()
        trainAI()
        print("--- CONVERSATION HISTORY RESET ---")
        hideSettings()
    }

    // MARK: - Theme & Persistence
    private func saveGameData() {
        UserDefaults.standard.set(currentThemeIndex, forKey: themeKey)
        UserDefaults.standard.set(userCurrency, forKey: currencyKey)
        let unlockedNames = themes.filter { $0.isUnlocked }.map { $0.name }
        UserDefaults.standard.set(unlockedNames, forKey: unlockedThemesKey)
        print("Game data saved. Currency: \(userCurrency)")
    }

    private func loadGameData() {
        userCurrency = UserDefaults.standard.integer(forKey: currencyKey)
        if let unlockedNames = UserDefaults.standard.array(forKey: unlockedThemesKey) as? [String] {
            for i in 0..<themes.count {
                if unlockedNames.contains(themes[i].name) {
                    themes[i].isUnlocked = true
                }
            }
            if UserDefaults.standard.object(forKey: themeKey) != nil {
                currentThemeIndex = UserDefaults.standard.integer(forKey: themeKey)
            }
        } else {
            var defaultIndex = 0
            for i in 0..<themes.count {
                themes[i].isUnlocked = (themes[i].price == 0)
                if themes[i].isUnlocked {
                    defaultIndex = i
                }
            }
            currentThemeIndex = defaultIndex
        }
        print("Game data loaded. Currency: \(userCurrency).")
    }
    
    func createGradientImage(from colors: [UIColor]) -> UIImage? {
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(x: 0, y: 0, width: 256, height: 256)
        gradientLayer.colors = colors.map { $0.cgColor }
        if colors.count > 2 {
            gradientLayer.locations = (0...colors.count-1).map { NSNumber(value: Double($0) / Double(colors.count - 1)) }
        }
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        UIGraphicsBeginImageContext(gradientLayer.bounds.size)
        if let context = UIGraphicsGetCurrentContext() {
            gradientLayer.render(in: context)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return image
        }
        return nil
    }
    
    private func updateTheme() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        let currentTheme = themes[currentThemeIndex]
        lockTextNode.opacity = 0.0
        sphereNode.opacity = 1.0
        floorNode.opacity = 1.0
        let isLocked = !currentTheme.isUnlocked
        applyThemeLook(theme: currentTheme, dimmed: isLocked)
        if isLocked {
            sphereNode.opacity = 0.3
            floorNode.opacity = 0.4
            
            let price = currentTheme.price
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            let formattedPrice = numberFormatter.string(from: NSNumber(value: price)) ?? "\(price)"

            if let lockGeometry = lockTextNode.geometry as? SCNText {
                lockGeometry.string = "💰 \(formattedPrice)"
                let (min, max) = lockTextNode.boundingBox
                lockTextNode.pivot = SCNMatrix4MakeTranslation((max.x - min.x)/2 + min.x, (max.y - min.y)/2 + min.y, 0)
            }

            lockTextNode.opacity = 1.0
        }
        SCNTransaction.commit()
    }

    private func applyThemeLook(theme: ColorTheme, dimmed: Bool) {
        let displayColor = theme.displayColor
        switch displayColor {
        case tangerineAquaPlaceholder: sphereNode.geometry?.firstMaterial?.diffuse.contents = createGradientImage(from: [tangerineColor, aquaColor])
        case indigoLimePlaceholder: sphereNode.geometry?.firstMaterial?.diffuse.contents = createGradientImage(from: [indigoColor, limeColor])
        case indigoRedPlaceholder: sphereNode.geometry?.firstMaterial?.diffuse.contents = createGradientImage(from: [indigoColor, redColor])
        case indigoYellowPlaceholder: sphereNode.geometry?.firstMaterial?.diffuse.contents = createGradientImage(from: [indigoColor, yellowColor])
        case limeOrangePlaceholder: sphereNode.geometry?.firstMaterial?.diffuse.contents = createGradientImage(from: [limeColor, tangerineColor])
        case blueRedPlaceholder: sphereNode.geometry?.firstMaterial?.diffuse.contents = createGradientImage(from: [blueColor, redColor])
        case triColorPlaceholder: sphereNode.geometry?.firstMaterial?.diffuse.contents = createGradientImage(from: [indigoColor, tangerineColor, limeColor])
        default: sphereNode.geometry?.firstMaterial?.diffuse.contents = displayColor
        }
        if !theme.displayColor.isPlaceholder {
            let bgColor = dimmed ? displayColor.desaturated(by: 0.8) : displayColor
            scnView.backgroundColor = bgColor
            floorNode.geometry?.firstMaterial?.diffuse.contents = bgColor
        }
        if dimmed { omniLightNode.light?.color = UIColor.gray }
        else { omniLightNode.light?.color = displayColor.isPlaceholder ? UIColor.white : (displayColor.lighter(by: 20) ?? .white) }
    }

    // MARK: - Gestures & Interaction
    @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .right:
            currentThemeIndex = (currentThemeIndex + 1) % themes.count
            updateTheme()
        case .left:
            currentThemeIndex = (currentThemeIndex - 1 + themes.count) % themes.count
            updateTheme()
        case .up:
            showChatHistory()
        default:
            break
        }
    }
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: scnView)
        let hitResults = scnView.hitTest(location, options: nil)
        
        guard hitResults.contains(where: { $0.node == sphereNode }) else { return }

        let currentTheme = themes[currentThemeIndex]
        
        if currentTheme.isUnlocked {
            tapAmplitude = 1.0
        } else {
            // --- MODIFIED: Show custom purchase screen instead of alert ---
            if userCurrency >= currentTheme.price {
                showPurchaseScreen()
            } else {
                shakeNode(lockTextNode)
            }
        }
    }

    func shakeNode(_ node: SCNNode) {
        let shakeAnimation = CAKeyframeAnimation(keyPath: "position.x")
        shakeAnimation.values = [0, 10, -10, 10, -5, 5, -2, 2, 0].map { node.presentation.position.x + Float($0 * 0.03) }
        shakeAnimation.keyTimes = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1]
        shakeAnimation.duration = 0.4
        node.addAnimation(shakeAnimation, forKey: "shake")
    }

    @objc func handleLongPress(_ gestureRecognize: UILongPressGestureRecognizer) {
        guard themes[currentThemeIndex].isUnlocked else { return }
        let currentColor = themes[currentThemeIndex].displayColor
        if gestureRecognize.state == .began {
            isRecording = true
            if !currentColor.isPlaceholder { sphereNode.geometry?.firstMaterial?.diffuse.contents = currentColor.lighter(by: 20) }
            sphereNode.geometry?.firstMaterial?.metalness.contents = 0.95
            sphereNode.geometry?.firstMaterial?.roughness.contents = 0.1
            startSpeechRecognition()
        } else if gestureRecognize.state == .ended {
            isRecording = false
            updateTheme()
            sphereNode.geometry?.firstMaterial?.metalness.contents = 0.9
            sphereNode.geometry?.firstMaterial?.roughness.contents = 0.2
            if audioEngine.isRunning { recognitionRequest?.endAudio() }
        }
    }

    // MARK: - Core Logic (Speech, Animation)
    func processUserInput(_ text:String){
        let userMessage = ChatMessage(id: UUID(), text: text, sender: .user, timestamp: Date())
        ChatHistoryManager.shared.save(message: userMessage)
        self.chatMessages.append(userMessage)
        
        userCurrency += 1
        print("Currency Earned! New Balance: \(userCurrency)")
        saveGameData()
        
        trainAI()

        if let response = aiResponseGenerator?(text) {
            self.speak(text: response)
        }
    }
    
    @objc func update() {
        let time = Float(CACurrentMediaTime())
        let progress = (sin(time * 0.5) + 1) / 2
        let currentTheme = themes[currentThemeIndex]
        let isLocked = !currentTheme.isUnlocked
        if currentTheme.displayColor.isPlaceholder {
            var animatedColor: UIColor?
            switch currentTheme.displayColor {
            case tangerineAquaPlaceholder: animatedColor = UIColor.interpolate(from: tangerineColor, to: aquaColor, with: CGFloat(progress))
            case indigoLimePlaceholder: animatedColor = UIColor.interpolate(from: indigoColor, to: limeColor, with: CGFloat(progress))
            case indigoRedPlaceholder: animatedColor = UIColor.interpolate(from: indigoColor, to: redColor, with: CGFloat(progress))
            case indigoYellowPlaceholder: animatedColor = UIColor.interpolate(from: indigoColor, to: yellowColor, with: CGFloat(progress))
            case limeOrangePlaceholder: animatedColor = UIColor.interpolate(from: limeColor, to: tangerineColor, with: CGFloat(progress))
            case blueRedPlaceholder: animatedColor = UIColor.interpolate(from: blueColor, to: redColor, with: CGFloat(progress))
            case triColorPlaceholder:
                if progress < 0.5 { animatedColor = UIColor.interpolate(from: indigoColor, to: tangerineColor, with: CGFloat(progress * 2)) }
                else { animatedColor = UIColor.interpolate(from: tangerineColor, to: limeColor, with: CGFloat((progress - 0.5) * 2)) }
            default: break
            }
            if let color = animatedColor {
                let finalColor = isLocked ? color.desaturated(by: 0.8) : color
                scnView.backgroundColor = finalColor
                floorNode.geometry?.firstMaterial?.diffuse.contents = finalColor
            }
        }
        directionalLightNode.position = SCNVector3(x: sin(time * 0.7) * 8.0, y: cos(time * 0.4) * 8.0 + 10, z: sin(time * 0.5) * 8.0)
        
        // --- MODIFIED ---: Unlocked the Z-axis movement for the first omni light.
        omniLightNode.position = SCNVector3(x: sin(time * 0.6 + cos(time * 0.3) * 0.5) * 5.0, y: cos(time * 0.5 + sin(time * 0.4) * 0.5) * 5.0 + 5, z: cos(time * 0.35) * 5.0)

        // --- ADDED ---: Set the position for the new, second omni light on every frame.
        // Using different multipliers ensures its movement is unique.
        secondOmniLightNode.position = SCNVector3(x: cos(time * 0.45) * 7.0, y: sin(time * 0.65) * 4.0 + 4.0, z: sin(time * 0.25) * 7.0)
        
        let sX = sin(time * 0.2) * 0.5, sY = cos(time * 0.4) * 0.5 + 0.5, sZ = sin(time * 0.3) * 0.5
        sphereNode.position = SCNVector3(x: sX, y: sY, z: sZ)
        textNode.position = SCNVector3(x: sX, y: sY + 3.0, z: sZ)
        tapAmplitude *= 0.85
        var combinedAmplitude: Float = audioAmplitude + tapAmplitude
        if isAssistantSpeaking {
            let lengthOfSpokenWord = Float(currentSpeechRange.length)
            let dynamicAmplitude = lengthOfSpokenWord > 0 ? sin(Float(CACurrentMediaTime()) * lengthOfSpokenWord) * 0.4 + 0.4 : 0.0
            combinedAmplitude += dynamicAmplitude
        }
        let scaleFactor = 1.0 + combinedAmplitude * 0.6
        sphereNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
    }
    
    func setupAudioEngine() {
        let audioSession = AVAudioSession.sharedInstance()
        do { try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers); try audioSession.setActive(true, options: .notifyOthersOnDeactivation) } catch { print("Audio session setup failed: \(error)") }
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, when) in
            self?.calculateAmplitude(buffer: buffer)
            if self?.isRecording ?? false { self?.recognitionRequest?.append(buffer) }
        }
        audioEngine.prepare()
        try? audioEngine.start()
    }
    
    func setupSpeechRecognizer() { SFSpeechRecognizer.requestAuthorization { _ in OperationQueue.main.addOperation { print("Speech recognition authorized.") } } }
    func setupDisplayLink() { displayLink = CADisplayLink(target: self, selector: #selector(update)); displayLink?.add(to: .main, forMode: .common) }
    
    func startSpeechRecognition() {
        if recognitionTask != nil { recognitionTask?.cancel(); recognitionTask = nil }
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError() }
        recognitionRequest.shouldReportPartialResults = true
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] (result, error) in
            var isFinal = false
            if let result = result {
                self?.updateTextDisplayLive(with: result.bestTranscription.formattedString)
                isFinal = result.isFinal
                if isFinal && !result.bestTranscription.formattedString.isEmpty {
                    self?.processUserInput(result.bestTranscription.formattedString)
                    self?.stopSpeechRecognition()
                    self?.clearTextDisplay()
                }
            }
            if error != nil || isFinal {
                self?.stopSpeechRecognition()
                self?.clearTextDisplay()
            }
        }
    }
    
    func stopSpeechRecognition() { recognitionRequest?.endAudio(); recognitionRequest = nil; recognitionTask?.cancel(); recognitionTask = nil }
    
    func calculateAmplitude(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelData0 = channelData.pointee
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames { sum += channelData0[i] * channelData0[i] }
        let rms = sqrt(sum / Float(frames))
        let normalizedValue = min(max(rms * 4.0, 0.0), 1.0)
        let alpha: Float = 0.4
        audioAmplitude = alpha * normalizedValue + (1.0 - alpha) * audioAmplitude
    }
    
    func updateTextDisplayLive(with recognizedText: String) {
        guard !recognizedText.isEmpty else { clearTextDisplay(); return }
        let newWords = recognizedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if let textGeometry = textNode.geometry as? SCNText, let currentDisplayedString = textGeometry.string as? String, let lastNewWord = newWords.last { if currentDisplayedString == lastNewWord { return } }
        if let lastWord = newWords.last {
            if let textGeometry = textNode.geometry as? SCNText {
                textGeometry.string = lastWord
                textGeometry.alignmentMode = CATextLayerAlignmentMode.center.rawValue
                let (min, max) = textNode.boundingBox
                textNode.pivot = SCNMatrix4MakeTranslation((max.x - min.x) / 2 + min.x, (max.y - min.y) / 2 + min.y, 0)
            }
            textNode.removeAllActions()
            textNode.opacity = 0.0
            textNode.runAction(SCNAction.fadeIn(duration: 0.1))
        } else { clearTextDisplay() }
    }
    
    func clearTextDisplay() { if let textGeometry = textNode.geometry as? SCNText { textGeometry.string = "" }; textNode.removeAllActions(); textNode.opacity = 0.0 }
    
    func speak(text: String) {
        let assistantMessage = ChatMessage(id: UUID(), text: text, sender: .assistant, timestamp: Date())
        ChatHistoryManager.shared.save(message: assistantMessage)
        self.chatMessages.append(assistantMessage)
        
        audioEngine.stop()
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: []); try AVAudioSession.sharedInstance().setActive(true) } catch { print("Failed to set audio session for playback: \(error)") }
        if speechSynthesizer.isSpeaking { speechSynthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        speechSynthesizer.delegate = self
        speechSynthesizer.speak(utterance)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) { isAssistantSpeaking = true }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isAssistantSpeaking = false
        currentSpeechRange = NSRange(location: 0, length: 0)
        do { try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: .duckOthers); try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation); try audioEngine.start() } catch { print("Failed to restore audio session: \(error)") }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) { isAssistantSpeaking = false }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) { isAssistantSpeaking = true }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) { currentSpeechRange = characterRange }
}

// MARK: - TableView DataSource & Delegate
extension GameViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return chatMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatBubbleCell", for: indexPath) as! ChatBubbleCell
        let message = chatMessages[(chatMessages.count - 1) - indexPath.row]
        cell.configure(with: message)
        return cell
    }
}

// MARK: - UIColor Extension
extension UIColor {
    func lighter(by percentage: CGFloat = 30.0) -> UIColor? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return UIColor(red: min(red + percentage/100, 1.0), green: min(green + percentage/100, 1.0), blue: min(blue + percentage/100, 1.0), alpha: alpha)
        }
        return nil
    }
    
    static func interpolate(from fromColor: UIColor, to toColor: UIColor, with progress: CGFloat) -> UIColor {
        var fromRed: CGFloat = 0, fromGreen: CGFloat = 0, fromBlue: CGFloat = 0, fromAlpha: CGFloat = 0
        fromColor.getRed(&fromRed, green: &fromGreen, blue: &fromBlue, alpha: &fromAlpha)
        var toRed: CGFloat = 0, toGreen: CGFloat = 0, toBlue: CGFloat = 0, toAlpha: CGFloat = 0
        toColor.getRed(&toRed, green: &toGreen, blue: &toBlue, alpha: &toAlpha)
        let red = fromRed + (toRed - fromRed) * progress
        let green = fromGreen + (toGreen - fromGreen) * progress
        let blue = fromBlue + (toBlue - fromBlue) * progress
        let alpha = fromAlpha + (toAlpha - fromAlpha) * progress
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    var isPlaceholder: Bool {
        var white: CGFloat = 0, alpha: CGFloat = 0
        self.getWhite(&white, alpha: &alpha)
        return white == 0.0 && alpha > 0.0 && alpha < 1.0
    }
    
    func desaturated(by percentage: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return UIColor(hue: hue, saturation: saturation * (1.0 - percentage), brightness: brightness * 0.5, alpha: alpha)
    }
}

// MARK: - Custom TableViewCell for Chat Bubbles
class ChatBubbleCell: UITableViewCell {
    
    private let bubbleView = UIView()
    private let messageLabel = UILabel()
    
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 18
        contentView.addSubview(bubbleView)
        
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.font = UIFont.systemFont(ofSize: 16)
        bubbleView.addSubview(messageLabel)
        
        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75),
            
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12)
        ])
        
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with message: ChatMessage) {
        messageLabel.text = message.text
        
        if message.sender == .user {
            bubbleView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
            messageLabel.textColor = .white
            leadingConstraint.isActive = false
            trailingConstraint.isActive = true
        } else {
            bubbleView.backgroundColor = .white
            messageLabel.textColor = .black
            leadingConstraint.isActive = true
            trailingConstraint.isActive = false
        }
    }
}
// MARK: - Markov Chain AI Logic
class MarkovChainGenerator {
    private struct WordPair: Hashable {
        let word1: String
        let word2: String
    }

    // --- ORIGINAL DATA STRUCTURE ---
    private var ngram: [WordPair: [String]] = [:]

    // --- NEW: Data structures for storing linguistic relationships ---
    private var nounVerbPairs: [String: [String]] = [:]
    private var adjectiveNounPairs: [String: [String]] = [:]

    private func clean(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ".", with: " .")
            .replacingOccurrences(of: "?", with: " ?")
            .replacingOccurrences(of: "!", with: " !")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
    }

    // --- MODIFIED: The training method now also learns POS relationships ---
    func train(with corpus: String) {
        // Reset all data structures
        ngram = [:]
        nounVerbPairs = [:]
        adjectiveNounPairs = [:]

        let sentences = corpus.components(separatedBy: .newlines)
        
        // Use a single NLTagger instance for efficiency
        let tagger = NLTagger(tagSchemes: [.lexicalClass])

        for sentence in sentences {
            let cleanedSentence = clean(sentence)
            let words = cleanedSentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            // 1. Train the original n-gram model
            if words.count >= 3 {
                for i in 2..<words.count {
                    let word1 = words[i - 2]
                    let word2 = words[i - 1]
                    let nextWord = words[i]
                    let wordPair = WordPair(word1: word1, word2: word2)
                    ngram[wordPair, default: []].append(nextWord)
                }
            }
            
            // 2. Train the new POS-based model
            tagger.string = cleanedSentence
            let tags = tagger.tags(in: cleanedSentence.startIndex..<cleanedSentence.endIndex, unit: .word, scheme: .lexicalClass)
            
            let taggedWords = tags.compactMap { tag, tokenRange -> (String, NLTag)? in
                guard let tag = tag else { return nil }
                return (String(cleanedSentence[tokenRange]), tag)
            }
            
            if taggedWords.count < 2 { continue }

            for i in 1..<taggedWords.count {
                let (previousWord, previousTag) = taggedWords[i - 1]
                let (currentWord, currentTag) = taggedWords[i]

                // Adjective -> Noun rule
                if previousTag == .adjective && currentTag == .noun {
                    adjectiveNounPairs[previousWord, default: []].append(currentWord)
                }
                
                // Noun -> Verb rule
                if previousTag == .noun && currentTag == .verb {
                    nounVerbPairs[previousWord, default: []].append(currentWord)
                }
            }
        }
    }

    // --- MODIFIED: The response generator now uses POS-biasing ---
    func generateResponse(for input: String) -> String {
        guard !ngram.isEmpty else {
            return "I'm still learning. Say something to get started!"
        }

        let cleanedInput = clean(input)
        let inputWords = cleanedInput.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        var startingPair: WordPair?
        if inputWords.count >= 2 {
            let lastWord = inputWords[inputWords.count - 1]
            let secondLastWord = inputWords[inputWords.count - 2]
            let potentialPair = WordPair(word1: secondLastWord, word2: lastWord)
            if ngram.keys.contains(potentialPair) {
                startingPair = potentialPair
            }
        }
        
        if startingPair == nil {
            startingPair = ngram.keys.randomElement()
        }
        
        guard var currentPair = startingPair else {
            return "I don't know how to respond to that yet."
        }

        var output = [currentPair.word1, currentPair.word2]
        let maxResponseLength = Int.random(in: 5...25)
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])

        for _ in 0..<maxResponseLength {
            var nextWord: String?
            let lastWord = output.last!
            
            tagger.string = lastWord
            let lastWordTag = tagger.tags(in: lastWord.startIndex..<lastWord.endIndex, unit: .word, scheme: .lexicalClass).first?.0

            // Apply biasing with a 50% chance to make it feel more natural
            if Int.random(in: 1...2) == 1 {
                if lastWordTag == .adjective, let possibleNouns = adjectiveNounPairs[lastWord] {
                    nextWord = possibleNouns.randomElement()
                } else if lastWordTag == .noun, let possibleVerbs = nounVerbPairs[lastWord] {
                    nextWord = possibleVerbs.randomElement()
                }
            }
            
            // If no bias was applied or possible, fall back to the standard Markov chain
            if nextWord == nil {
                if let nextWords = ngram[currentPair] {
                    nextWord = nextWords.randomElement()
                } else {
                    break // Dead end
                }
            }
            
            guard let finalNextWord = nextWord else { break }
            
            output.append(finalNextWord)
            
            if finalNextWord == "." || finalNextWord == "?" || finalNextWord == "!" {
                break
            }
            
            currentPair = WordPair(word1: currentPair.word2, word2: finalNextWord)
        }
        
        let joinedOutput = output.joined(separator: " ")
        let formattedOutput = joinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                                   .replacingOccurrences(of: " .", with: ".")
                                   .replacingOccurrences(of: " ?", with: "?")
                                   .replacingOccurrences(of: " !", with: "!")
        
        return formattedOutput.prefix(1).capitalized + formattedOutput.dropFirst()
    }
}

