import UIKit
import Vision
import AVFoundation
import CoreMedia
import CoreLocation
import UserNotifications
import Alamofire
import Speech
import UberRides


class ViewController: UIViewController, CLLocationManagerDelegate {
    
    
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var debugImageView: UIImageView!
    @IBOutlet weak var descriptionLabel: UILabel!
    var count: Int = 0
    let audioEngine = AVAudioEngine()
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    let request = SFSpeechAudioBufferRecognitionRequest()
    var recognitionTask: SFSpeechRecognitionTask?
    //  var recognitionString: String!
    var muted: Bool = false


    var longitude: Double!
    var latitude: Double!

    let locationManager = CLLocationManager()
    var currentLocation: CLLocation!
    let synthesizer = AVSpeechSynthesizer()

    var audioPlayer = AVAudioPlayer()

    //Create new array that has less of the boxes
    var boundingBoxesEdited = Array<BoundingBox>()
    var i : Int = 100

    // true: use Vision to drive Core ML, false: use plain Core ML
    let useVision = false

    // Disable this to see the energy impact of just running the neural net,
    // otherwise it also counts the GPU activity of drawing the bounding boxes.
    let drawBoundingBoxes = true

    // H.
    static let maxInflightBuffers = 1

    let yolo = YOLO()

    var videoCapture: VideoCapture!
    var requests = [VNCoreMLRequest]()
    var startTimes: [CFTimeInterval] = []

    var boundingBoxes = [BoundingBox]()
    var colors: [UIColor] = []

    let ciContext = CIContext()
    var resizedPixelBuffers: [CVPixelBuffer?] = []

    var framesDone = 0
    var frameCapturingStartTime = CACurrentMediaTime()

    var inflightBuffer = 0
    let semaphore = DispatchSemaphore(value: ViewController.maxInflightBuffers)
    //This is the uber button
    let uberButton = RideRequestButton()

    

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        //Checking to see if the app has launched before or not
        let launchedBefore = UserDefaults.standard.bool(forKey: "launched")
        if launchedBefore {
            print("Not first launch.")
            SpeechService.shared.speak(text: "App is detecting Objects") {}
        } else {
            print("First launch, setting UserDefault.")
            SpeechService.shared.speak(text: "Welcome to smart eyes, using machine learning to help you see") {}

            UserDefaults.standard.set(true, forKey: "launched")
        }
    }
    
    
  override func viewDidLoad() {
    super.viewDidLoad()
    //Location purposes
    locationManager.delegate = self
    locationManager.requestAlwaysAuthorization()
    locationManager.startUpdatingLocation()
    locationManager.distanceFilter = 1
    let geofencing:CLCircularRegion = CLCircularRegion(center: CLLocationCoordinate2DMake(40.694255, -73.986793), radius: 30, identifier: "Intersection")
    locationManager.startMonitoring(for: geofencing)
    descriptionLabel.text = ""
    setUpBoundingBoxes()
    setUpCoreImage()
    setUpVision()
    setUpCamera()
    
    debugImageView.addSubview(descriptionLabel)
    
    //Single Tap Gesture Recognizer
    let singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(didPressPartButton))
    singleTapGesture.numberOfTapsRequired = 2
    view.addGestureRecognizer(singleTapGesture)
    
    //Double Tap Gesture Recognizer
    let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap))
    doubleTapGesture.numberOfTapsRequired = 3
    view.addGestureRecognizer(doubleTapGesture)
    singleTapGesture.require(toFail: doubleTapGesture)
    
    //Hold Tap Gesture Recognizer
    let longTapRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(didLongTap))
    view.addGestureRecognizer(longTapRecognizer)
    frameCapturingStartTime = CACurrentMediaTime()
    locationManager.requestWhenInUseAuthorization()
    
    if( CLLocationManager.authorizationStatus() == .authorizedWhenInUse ||
        CLLocationManager.authorizationStatus() ==  .authorizedAlways){
        currentLocation = locationManager.location
    }
    
    let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(respondToSwipeGesture(gesture:)))
    swipeUp.direction = UISwipeGestureRecognizer.Direction.up
    self.view.addGestureRecognizer(swipeUp)
    let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(respondToSwipeGesture(gesture:)))
    swipeDown.direction = UISwipeGestureRecognizer.Direction.down
    self.view.addGestureRecognizer(swipeDown)
    
    let dropoffLocation = CLLocation(latitude: 47.642146, longitude: -122.137085)
    let builder = RideParametersBuilder()
    builder.dropoffLocation = dropoffLocation
    builder.dropoffNickname = "Home"
    uberButton.rideParameters = builder.build()
   
    //Adding the uberbutton to the imageview
    view.addSubview(uberButton)
    setupUberLayout()
    
    //Swipe right gesture recognition
    let rightswipe = UISwipeGestureRecognizer(target: self, action: #selector(rightSwipe))
    rightswipe.direction = .right
    self.view.addGestureRecognizer(rightswipe)
    
  }
    
    func setupUberLayout() {
        uberButton.translatesAutoresizingMaskIntoConstraints = false
        uberButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        uberButton.topAnchor.constraint(equalTo: debugImageView.bottomAnchor).isActive = true
    }
    
    @objc func rightSwipe() {
        print("Supposed to launch uber")
        
    }
    
    
    @objc func respondToSwipeGesture(gesture: UIGestureRecognizer) {
        if let swipeGesture = gesture as? UISwipeGestureRecognizer {
            switch swipeGesture.direction {
            case UISwipeGestureRecognizer.Direction.down:
                break
            default:
                print("None")
        }
    }
        
}
    
    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    
    @objc func didPressPartButton() {
        print("Testing")
            guard let device = AVCaptureDevice.default(for: AVMediaType.video) else { return }
            guard device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                
                if (device.torchMode == AVCaptureDevice.TorchMode.on) {
                    device.torchMode = AVCaptureDevice.TorchMode.off
                    SpeechService.shared.speak(text: "Flash light has been turned off") {}
                } else {
                    do {
                        try device.setTorchModeOn(level: 1.0)
                        SpeechService.shared.speak(text: "Flash light has been turned on") {}
                    } catch {
                        
                    }
                }
                device.unlockForConfiguration()
            } catch {
                print(error)
            }
    }
    
    @objc func didDoubleTap() {
        
        SpeechService.shared.speak(text: "Message Has been sent") {}
        
        Alamofire.request("http://138.51.33.200:8000/message", method: .get).responseJSON { _ in}
    }
    
    
    @objc func didLongTap(recognizer: UIGestureRecognizer) {
        if recognizer.state == .began {

            SpeechService.shared.speak(text: "The following sound is for a person") {
                //Play the sound of a person
                self.playsound(name: "footstep")
                
                SpeechService.shared.speak(text: "for a chair") {
                    //Play the sound of a chair
                    self.playsound(name: "chair")

                    SpeechService.shared.speak(text: "for a dog") {
                        //Play the sound of a dog
                        self.playsound(name: "dog")

                        SpeechService.shared.speak(text: "for a cat") {
                            //Play the sound of a cat
                            self.playsound(name: "cat")

                            SpeechService.shared.speak(text: "for a bike") {
                                //Play the sound of a bike
                                self.playsound(name: "bike-bell")
                                SpeechService.shared.speak(text: "for a car") {
                                    //Play the sound of a car
                                    self.playsound(name: "car-honk")

                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func playsound(name:String) {
    
        let alertSound = URL(fileURLWithPath: Bundle.main.path(forResource: "\(name)", ofType: "mp3")!)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }
        // Play the sound
        do {
            self.audioPlayer = try AVAudioPlayer(contentsOf: alertSound)
        } catch _{
            
        }
        self.audioPlayer.volume = 1.0
        self.audioPlayer.prepareToPlay()
        self.audioPlayer.play()
    }
    
    
    
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
//        for currentLocation in locations {
//            print("\(index): \(currentLocation)")
//        }
    }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    print(#function)
  }

  // MARK: - Initialization

  func setUpBoundingBoxes() {
    for _ in 0..<YOLO.maxBoundingBoxes {
      boundingBoxesEdited.append(BoundingBox())
    }
    // Make colors for the bounding boxes. There is one color for each class,
    // 20 classes in total.
    for r: CGFloat in [0.2, 0.4, 0.6, 0.8, 1.0] {
      for g: CGFloat in [0.3, 0.7] {
        for b: CGFloat in [0.4, 0.8] {
          let color = UIColor(red: r, green: g, blue: b, alpha: 1)
          colors.append(color)
        }
      }
    }
  }

  func setUpCoreImage() {
    // Since we might be running several requests in parallel, we also need
    // to do the resizing in different pixel buffers or we might overwrite a
    // pixel buffer that's already in use.
    for _ in 0..<YOLO.maxBoundingBoxes {
      var resizedPixelBuffer: CVPixelBuffer?
      let status = CVPixelBufferCreate(nil, YOLO.inputWidth, YOLO.inputHeight,
                                       kCVPixelFormatType_32BGRA, nil,
                                       &resizedPixelBuffer)

      if status != kCVReturnSuccess {
        print("Error: could not create resized pixel buffer", status)
      }
      resizedPixelBuffers.append(resizedPixelBuffer)
    }
  }

  func setUpVision() {
    guard let visionModel = try? VNCoreMLModel(for: yolo.model.model) else {
      print("Error: could not create Vision model")
      return
    }

    for _ in 0..<ViewController.maxInflightBuffers {
      let request = VNCoreMLRequest(model: visionModel, completionHandler: visionRequestDidComplete)

      // NOTE: If you choose another crop/scale option, then you must also
      // change how the BoundingBox objects get scaled when they are drawn.
      // Currently they assume the full input image is used.
      request.imageCropAndScaleOption = .scaleFill
      requests.append(request)
    }
  }
    
 

  func setUpCamera() {
    videoCapture = VideoCapture()
    videoCapture.delegate = self
    videoCapture.desiredFrameRate = 30
    videoCapture.setUp(sessionPreset: AVCaptureSession.Preset.hd1280x720) { success in
      if success {
        // Add the video preview into the UI.
        if let previewLayer = self.videoCapture.previewLayer {
          self.videoPreview.layer.addSublayer(previewLayer)
          self.resizePreviewLayer()
        }

        // Add the bounding box layers to the UI, on top of the video preview.
        for box in self.boundingBoxesEdited {
          box.addToLayer(self.videoPreview.layer)
        }

        // Once everything is set up, we can start capturing live video.
        self.videoCapture.start()
      }
    }
  }

  // MARK: - UI stuff
  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    resizePreviewLayer()
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }

  func resizePreviewLayer() {
    videoCapture.previewLayer?.frame = videoPreview.bounds
  }

  // MARK: - Doing inference
  func predict(image: UIImage) {
    if let pixelBuffer = image.pixelBuffer(width: YOLO.inputWidth, height: YOLO.inputHeight) {
      predict(pixelBuffer: pixelBuffer, inflightIndex: 0)
    }
  }

  func predict(pixelBuffer: CVPixelBuffer, inflightIndex: Int) {
    // Measure how long it takes to predict a single video frame.
    let startTime = CACurrentMediaTime()

    // This is an alternative way to resize the image (using vImage):
    //if let resizedPixelBuffer = resizePixelBuffer(pixelBuffer,
    //                                              width: YOLO.inputWidth,
    //                                              height: YOLO.inputHeight) {

    // Resize the input with Core Image to 416x416.
    if let resizedPixelBuffer = resizedPixelBuffers[inflightIndex] {
      let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
      let sx = CGFloat(YOLO.inputWidth) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
      let sy = CGFloat(YOLO.inputHeight) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
      let scaleTransform = CGAffineTransform(scaleX: sx, y: sy)
      let scaledImage = ciImage.transformed(by: scaleTransform)
      ciContext.render(scaledImage, to: resizedPixelBuffer)

      // Give the resized input to our model.
      if let result = try? yolo.predict(image: resizedPixelBuffer),
         let boundingBoxes = result {
        let elapsed = CACurrentMediaTime() - startTime
        showOnMainThread(boundingBoxes, elapsed)
      } else {
        print("BOGUS")
      }
    }

    self.semaphore.signal()
  }

  func predictUsingVision(pixelBuffer: CVPixelBuffer, inflightIndex: Int) {
    // Measure how long it takes to predict a single video frame. Note that
    // predict() can be called on the next frame while the previous one is
    // still being processed. Hence the need to queue up the start times.
    startTimes.append(CACurrentMediaTime())

    // Vision will automatically resize the input image.
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
    let request = requests[inflightIndex]

    // Because perform() will block until after the request completes, we
    // run it on a concurrent background queue, so that the next frame can
    // be scheduled in parallel with this one.
    DispatchQueue.global().async {
      try? handler.perform([request])
    }
  }

  func visionRequestDidComplete(request: VNRequest, error: Error?) {
    if let observations = request.results as? [VNCoreMLFeatureValueObservation],
       let features = observations.first?.featureValue.multiArrayValue {

      let boundingBoxes = yolo.computeBoundingBoxes(features: features)
      let elapsed = CACurrentMediaTime() - startTimes.remove(at: 0)
      showOnMainThread(boundingBoxes, elapsed)
    } else {
      print("BOGUS!")
    }

    self.semaphore.signal()
  }

  func showOnMainThread(_ boundingBoxes: [YOLO.Prediction], _ elapsed: CFTimeInterval) {
    if drawBoundingBoxes {
      DispatchQueue.main.async {
        // For debugging, to make sure the resized CVPixelBuffer is correct.
        //var debugImage: CGImage?
        //VTCreateCGImageFromCVPixelBuffer(resizedPixelBuffer, nil, &debugImage)
        //self.debugImageView.image = UIImage(cgImage: debugImage!)

        self.show(predictions: boundingBoxes)
      }
    }
  }

  func measureFPS() -> Double {
    // Measure how many frames were actually delivered per second.
    framesDone += 1
    let frameCapturingElapsed = CACurrentMediaTime() - frameCapturingStartTime
    let currentFPSDelivered = Double(framesDone) / frameCapturingElapsed
    if frameCapturingElapsed > 1 {
      framesDone = 0
      frameCapturingStartTime = CACurrentMediaTime()
    }
    return currentFPSDelivered
  }
    

  //Taking care of the entering and exiting the intersection area
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("Entering location")
//        let utterance = AVSpeechUtterance(string: "Entering Intersection")
//        synthesizer.speak(utterance)
        SpeechService.shared.speak(text: "Entering Intersection") {
            //Finished speaking
        }
        //Local Notification
        let content = UNMutableNotificationContent()
        content.title = "Warning"
        content.subtitle = "Crossing Road"
        content.body = "You are about to cross the road"
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: "Intersection", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        SpeechService.shared.speak(text: "Exiting Intersection") {}
        
        //Local Notification
        let content = UNMutableNotificationContent()
        content.title = "Notification"
        content.subtitle = "Exiting Intersection"
        content.body = "You are about to exit an intersection"
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: "Intersection", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

  func show(predictions: [YOLO.Prediction]) {
    //This goes through all the boxes, what we can test is to reduce this number for better results
    for frames in boundingBoxes {
        if (i%100 == 0) {
            boundingBoxesEdited.append(frames)
        }
        i = i + 100
    }
    
    
    
    for i in 0..<boundingBoxesEdited.count {
        if count%50 == 0 {
            if i < predictions.count {
                let prediction = predictions[i]
                
                // The predicted bounding box is in the coordinate space of the input
                // image, which is a square image of 416x416 pixels. We want to show it
                // on the video preview, which is as wide as the screen and has a 16:9
                // aspect ratio. The video preview also may be letterboxed at the top
                // and bottom.
                let width = view.bounds.width
                let height = width * 16 / 9
                let scaleX = width / CGFloat(YOLO.inputWidth)
                let scaleY = height / CGFloat(YOLO.inputHeight)
                let top = (view.bounds.height - height) / 2
                
                // Translate and scale the rectangle to our own coordinate system.
                var rect = prediction.rect
                rect.origin.x *= scaleX
                rect.origin.y *= scaleY
                rect.origin.y += top
                rect.size.width *= scaleX
                rect.size.height *= scaleY
                
                // Show the bounding box.
                //Making a condition to not show the box until the prediction is greater thatn 50%
                if prediction.score * 100 > 59 {
                    let label = String(format: "%@", labels[prediction.classIndex])
                    let color = colors[prediction.classIndex]
                    boundingBoxesEdited[i].show(frame: rect, label: label, color: color)
                    // Set the sound file name & extension
                    
                    
                    //Creating print statements that will show an object on left side of right side of the screen.
                    let coordinate = boundingBoxesEdited[i].getLocation(frame: rect)
                    let frameWidth = boundingBoxesEdited[i].getSize(frame: rect).width
                    let frameHeight = boundingBoxesEdited[i].getSize(frame: rect).height
                    let area = frameWidth * frameHeight
                    
             
                    //Need to spedicy if its a person label
                    if "\(labels[prediction.classIndex])" == "person" {
                        let alertSound = URL(fileURLWithPath: Bundle.main.path(forResource: "footstep", ofType: "mp3")!)
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                            try AVAudioSession.sharedInstance().setActive(true)
                        } catch {
                            print(error)
                        }
                        // Play the sound
                        do {
                            audioPlayer = try AVAudioPlayer(contentsOf: alertSound)
                        } catch _{
                            
                        }
                        
                        
                        if coordinate.x < 25 {
                            descriptionLabel.text = "Person on the left"
                            //Used to make it so it only shows up on the right side
                            audioPlayer.pan = -1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 70000 {
                                audioPlayer.volume = 0.05
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.5
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.75
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                            
                         //Need to have it so that its a little bit in the left and in the middle
                        } else if coordinate.x >= 25 && coordinate.x <= 85 {
                            descriptionLabel.text = "Person a little to the left"
                            audioPlayer.pan = -0.5
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else if coordinate.x >= 85 && coordinate.x <= 135 {
                            descriptionLabel.text = "There is a person infront of you"
                            audioPlayer.pan = 0.0
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        //Need to have it so that if its a little bit to the right and a little bit in the middle.
                        } else if coordinate.x >= 135 && coordinate.x <= 185 {
                            descriptionLabel.text = "Person a little to the right"
                            audioPlayer.pan = 0.5
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
 
                        }else {
                            descriptionLabel.text = "Person on the right"
                            //Used to make it so it only shows up on the left side
                            audioPlayer.pan = 1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 7000 {
                                audioPlayer.volume = 0.05
                            }else if area >= 7000 && area < 14000 {
                                audioPlayer.volume = 0.5
                            }else if area >= 14000 && area <= 21000 {
                                audioPlayer.volume = 0.75
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                        }
                    }
                    
                    if "\(labels[prediction.classIndex])" == "dog" {
                        
                        
                        let alertSound = URL(fileURLWithPath: Bundle.main.path(forResource: "dog", ofType: "mp3")!)
                        
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                            try AVAudioSession.sharedInstance().setActive(true)
                        } catch {
                            print(error)
                        }
                        // Play the sound
                        do {
                            audioPlayer = try AVAudioPlayer(contentsOf: alertSound)
                        } catch _{}
                        
                        if coordinate.x < 55 {
                            descriptionLabel.text = "dog on the left"
                            //Used to make it so it only shows up on the right side
                            audioPlayer.pan = -1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.3
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.5
                            }else {
                                audioPlayer.volume = 0.75
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else if coordinate.x >= 55 && coordinate.x <= 145 {
                            descriptionLabel.text = "There is a dog infront of you"
                            if area <= 70000 {
                                audioPlayer.volume = 0.2
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else {
                            descriptionLabel.text = "dog on the right"
                            //Used to make it so it only shows up on the left side
                            audioPlayer.pan = 1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 7000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 7000 && area < 14000 {
                                audioPlayer.volume = 0.3
                            }else if area >= 14000 && area <= 21000 {
                                audioPlayer.volume = 0.5
                            }else {
                                audioPlayer.volume = 0.75
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                        }
                    }
                    
                    if "\(labels[prediction.classIndex])" == "cat" {
                        let alertSound = URL(fileURLWithPath: Bundle.main.path(forResource: "cat", ofType: "mp3")!)
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                            try AVAudioSession.sharedInstance().setActive(true)
                        } catch {
                            print(error)
                        }
                        // Play the sound
                        do {
                            audioPlayer = try AVAudioPlayer(contentsOf: alertSound)
                        } catch _{
                            
                        }
                        
                        
                        if coordinate.x < 55 {
                            descriptionLabel.text = "cat on the left"
                            //Used to make it so it only shows up on the right side
                            audioPlayer.pan = -1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.3
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.5
                            }else {
                                audioPlayer.volume = 0.75
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else if coordinate.x >= 55 && coordinate.x <= 145 {
                            descriptionLabel.text = "There is a cat infront of you"
                            if area <= 70000 {
                                audioPlayer.volume = 0.2
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else {
                            descriptionLabel.text = "cat on the right"
                            //Used to make it so it only shows up on the left side
                            audioPlayer.pan = 1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 7000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 7000 && area < 14000 {
                                audioPlayer.volume = 0.3
                            }else if area >= 14000 && area <= 21000 {
                                audioPlayer.volume = 0.5
                            }else {
                                audioPlayer.volume = 0.75
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                        }
                    }
                    
                    if "\(labels[prediction.classIndex])" == "car" {
                        
                        
                        let alertSound = URL(fileURLWithPath: Bundle.main.path(forResource: "car-honk", ofType: "mp3")!)
                        
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                            try AVAudioSession.sharedInstance().setActive(true)
                        } catch {
                            print(error)
                        }
                        
                        // Play the sound
                        do {
                            audioPlayer = try AVAudioPlayer(contentsOf: alertSound)
                        } catch _{
                            
                        }
                        
                        
                        if coordinate.x < 55 {
                            descriptionLabel.text = "car on the left"
                            //Used to make it so it only shows up on the right side
                            audioPlayer.pan = -1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.25
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.5
                            }else {
                                audioPlayer.volume = 0.75
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else if coordinate.x >= 55 && coordinate.x <= 145 {
                            descriptionLabel.text = "There is a car infront of you"
                            if area <= 70000 {
                                audioPlayer.volume = 0.2
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else {
                            descriptionLabel.text = "car on the right"
                            //Used to make it so it only shows up on the left side
                            audioPlayer.pan = 1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 7000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 7000 && area < 14000 {
                                audioPlayer.volume = 0.25
                            }else if area >= 14000 && area <= 21000 {
                                audioPlayer.volume = 0.5
                            }else {
                                audioPlayer.volume = 0.75
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                        }
                    }
                    
                    if "\(labels[prediction.classIndex])" == "bicycle" {
                        
                        
                        let alertSound = URL(fileURLWithPath: Bundle.main.path(forResource: "bike-bell", ofType: "mp3")!)
                        
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                            try AVAudioSession.sharedInstance().setActive(true)
                        } catch {
                            print(error)
                        }
                        
                        // Play the sound
                        do {
                            audioPlayer = try AVAudioPlayer(contentsOf: alertSound)
                        } catch _{
                            
                        }
                        
                        
                        if coordinate.x < 55 {
                            descriptionLabel.text = "bike on the left"
                            //Used to make it so it only shows up on the right side
                            audioPlayer.pan = -1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.5
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.75
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else if coordinate.x >= 55 && coordinate.x <= 145 {
                            descriptionLabel.text = "There is a bike infront of you"
                            if area <= 70000 {
                                audioPlayer.volume = 0.2
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else {
                            descriptionLabel.text = "bike on the right"
                            //Used to make it so it only shows up on the left side
                            audioPlayer.pan = 1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 7000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 7000 && area < 14000 {
                                audioPlayer.volume = 0.5
                            }else if area >= 14000 && area <= 21000 {
                                audioPlayer.volume = 0.75
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                        }
                    }
                    
                    if "\(labels[prediction.classIndex])" == "chair" {
                        
                        
                        let alertSound = URL(fileURLWithPath: Bundle.main.path(forResource: "chair", ofType: "mp3")!)
                        
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                            try AVAudioSession.sharedInstance().setActive(true)
                        } catch {
                            print(error)
                        }
                        
                        // Play the sound
                        do {
                            audioPlayer = try AVAudioPlayer(contentsOf: alertSound)
                        } catch _{
                            
                        }
                        
                        
                        if coordinate.x < 25 {
                            descriptionLabel.text = "Chair on the left"
                            //Used to make it so it only shows up on the right side
                            audioPlayer.pan = -1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 70000 {
                                audioPlayer.volume = 0.05
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.5
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.75
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                            
                            //Need to have it so that its a little bit in the left and in the middle
                        } else if coordinate.x >= 25 && coordinate.x <= 85 {
                            descriptionLabel.text = "Chair a little to the left"
                            audioPlayer.pan = -0.5
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        } else if coordinate.x >= 85 && coordinate.x <= 135 {
                            descriptionLabel.text = "There is a Chair infront of you"
                            audioPlayer.pan = 0.0
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                            //Need to have it so that if its a little bit to the right and a little bit in the middle.
                        } else if coordinate.x >= 135 && coordinate.x <= 185 {
                            descriptionLabel.text = "Chair a little to the right"
                            audioPlayer.pan = 0.5
                            if area <= 70000 {
                                audioPlayer.volume = 0.1
                            }else if area >= 70000 && area < 140000 {
                                audioPlayer.volume = 0.6
                            }else if area >= 140000 && area <= 210000 {
                                audioPlayer.volume = 0.8
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                            
                        }else {
                            descriptionLabel.text = "Chair on the right"
                            //Used to make it so it only shows up on the left side
                            audioPlayer.pan = 1.0
                            //Specifying the volume control depending on the frame area size
                            if area <= 7000 {
                                audioPlayer.volume = 0.05
                            }else if area >= 7000 && area < 14000 {
                                audioPlayer.volume = 0.5
                            }else if area >= 14000 && area <= 21000 {
                                audioPlayer.volume = 0.75
                            }else {
                                audioPlayer.volume = 1.0
                            }
                            audioPlayer.prepareToPlay()
                            audioPlayer.play()
                        }
                    }
                }
                
            } else {
                //If the prediction is less than 50%
                boundingBoxesEdited[i].hide()
            }
        }
        count += 1
        
    }
  }
}

extension ViewController: VideoCaptureDelegate {
  func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
    // For debugging.
    //predict(image: UIImage(named: "dog416")!); return

    if let pixelBuffer = pixelBuffer {
      // The semaphore will block the capture queue and drop frames when
      // Core ML can't keep up with the camera.
      semaphore.wait()

      // For better throughput, we want to schedule multiple prediction requests
      // in parallel. These need to be separate instances, and inflightBuffer is
      // the index of the current request.
      let inflightIndex = inflightBuffer
      inflightBuffer += 1
      if inflightBuffer >= ViewController.maxInflightBuffers {
        inflightBuffer = 0
      }

      if useVision {
        // This method should always be called from the same thread!
        // Ain't nobody likes race conditions and crashes.
        self.predictUsingVision(pixelBuffer: pixelBuffer, inflightIndex: inflightIndex)
      } else {
        // For better throughput, perform the prediction on a concurrent
        // background queue instead of on the serial VideoCapture queue.
        DispatchQueue.global().async {
                self.predict(pixelBuffer: pixelBuffer, inflightIndex: inflightIndex)
        }
      }
    }
  }
}


