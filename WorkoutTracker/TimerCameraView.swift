import SwiftUI
import AVFoundation

struct TimerCameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    let poseLabel: String

    func makeUIViewController(context: Context) -> TimerCameraViewController {
        let vc = TimerCameraViewController()
        vc.poseLabel = poseLabel
        vc.onCapture = { img in
            image = img
            dismiss()
        }
        vc.onCancel = { dismiss() }
        return vc
    }

    func updateUIViewController(_ uiViewController: TimerCameraViewController, context: Context) {}
}

class TimerCameraViewController: UIViewController {
    var poseLabel: String = ""
    var onCapture: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private var captureSession: AVCaptureSession?
    private var photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var timerDelay: Int = 5  // default 5s
    private var countdown: Int = 0
    private var countdownTimer: Timer?

    private let timerOptions = [0, 3, 5, 10]

    private var capturedImage: UIImage?

    // UI elements — camera
    private var countdownLabel: UILabel!
    private var poseNameLabel: UILabel!
    private var shutterButton: UIButton!
    private var cancelButton: UIButton!
    private var timerSegment: UISegmentedControl!
    private var flashView: UIView!

    // UI elements — review
    private var reviewContainer: UIView!
    private var reviewImageView: UIImageView!
    private var usePhotoButton: UIButton!
    private var retakeButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        countdownTimer?.invalidate()
        captureSession?.stopRunning()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    private func setupUI() {
        // Pose label at top
        poseNameLabel = UILabel()
        poseNameLabel.text = poseLabel.uppercased()
        poseNameLabel.font = .systemFont(ofSize: 13, weight: .bold)
        poseNameLabel.textColor = .white
        poseNameLabel.textAlignment = .center
        poseNameLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        poseNameLabel.layer.cornerRadius = 8
        poseNameLabel.clipsToBounds = true
        poseNameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(poseNameLabel)

        // Timer selector
        timerSegment = UISegmentedControl(items: timerOptions.map { $0 == 0 ? "OFF" : "\($0)s" })
        timerSegment.selectedSegmentIndex = timerOptions.firstIndex(of: timerDelay) ?? 2
        timerSegment.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        timerSegment.selectedSegmentTintColor = UIColor(red: 0.2, green: 0.83, blue: 0.6, alpha: 1) // accent
        timerSegment.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .bold)], for: .normal)
        timerSegment.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 12, weight: .bold)], for: .selected)
        timerSegment.addTarget(self, action: #selector(timerChanged), for: .valueChanged)
        timerSegment.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timerSegment)

        // Countdown label (big, centered)
        countdownLabel = UILabel()
        countdownLabel.font = .systemFont(ofSize: 120, weight: .black)
        countdownLabel.textColor = .white
        countdownLabel.textAlignment = .center
        countdownLabel.alpha = 0
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countdownLabel)

        // Shutter button
        shutterButton = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 60, weight: .regular)
        shutterButton.setImage(UIImage(systemName: "circle.inset.filled", withConfiguration: config), for: .normal)
        shutterButton.tintColor = .white
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutterButton)

        // Cancel button
        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Flash overlay for capture feedback
        flashView = UIView()
        flashView.backgroundColor = .white
        flashView.alpha = 0
        flashView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(flashView)

        // Review container (hidden initially)
        reviewContainer = UIView()
        reviewContainer.backgroundColor = .black
        reviewContainer.isHidden = true
        reviewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reviewContainer)

        reviewImageView = UIImageView()
        reviewImageView.contentMode = .scaleAspectFit
        reviewImageView.translatesAutoresizingMaskIntoConstraints = false
        reviewContainer.addSubview(reviewImageView)

        retakeButton = UIButton(type: .system)
        retakeButton.setTitle("Retake", for: .normal)
        retakeButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        retakeButton.tintColor = .white
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
        retakeButton.translatesAutoresizingMaskIntoConstraints = false
        reviewContainer.addSubview(retakeButton)

        usePhotoButton = UIButton(type: .system)
        usePhotoButton.setTitle("Use Photo", for: .normal)
        usePhotoButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        usePhotoButton.tintColor = UIColor(red: 0.2, green: 0.83, blue: 0.6, alpha: 1)
        usePhotoButton.addTarget(self, action: #selector(usePhotoTapped), for: .touchUpInside)
        usePhotoButton.translatesAutoresizingMaskIntoConstraints = false
        reviewContainer.addSubview(usePhotoButton)

        NSLayoutConstraint.activate([
            poseNameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            poseNameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            poseNameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            poseNameLabel.heightAnchor.constraint(equalToConstant: 32),

            timerSegment.topAnchor.constraint(equalTo: poseNameLabel.bottomAnchor, constant: 12),
            timerSegment.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerSegment.widthAnchor.constraint(equalToConstant: 220),

            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancelButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),

            flashView.topAnchor.constraint(equalTo: view.topAnchor),
            flashView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            flashView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            flashView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Review container
            reviewContainer.topAnchor.constraint(equalTo: view.topAnchor),
            reviewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            reviewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reviewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            reviewImageView.topAnchor.constraint(equalTo: reviewContainer.safeAreaLayoutGuide.topAnchor),
            reviewImageView.leadingAnchor.constraint(equalTo: reviewContainer.leadingAnchor),
            reviewImageView.trailingAnchor.constraint(equalTo: reviewContainer.trailingAnchor),
            reviewImageView.bottomAnchor.constraint(equalTo: retakeButton.topAnchor, constant: -20),

            retakeButton.bottomAnchor.constraint(equalTo: reviewContainer.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            retakeButton.leadingAnchor.constraint(equalTo: reviewContainer.leadingAnchor, constant: 40),

            usePhotoButton.bottomAnchor.constraint(equalTo: reviewContainer.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            usePhotoButton.trailingAnchor.constraint(equalTo: reviewContainer.trailingAnchor, constant: -40),
        ])
    }

    private func showReview(image: UIImage) {
        capturedImage = image
        reviewImageView.image = image
        reviewContainer.isHidden = false
    }

    @objc private func retakeTapped() {
        capturedImage = nil
        reviewContainer.isHidden = true
        shutterButton.isEnabled = true
        timerSegment.isUserInteractionEnabled = true
    }

    @objc private func usePhotoTapped() {
        guard let image = capturedImage else { return }
        onCapture?(image)
    }

    @objc private func timerChanged() {
        timerDelay = timerOptions[timerSegment.selectedSegmentIndex]
    }

    @objc private func shutterTapped() {
        if timerDelay == 0 {
            capturePhoto()
        } else {
            startCountdown()
        }
    }

    @objc private func cancelTapped() {
        countdownTimer?.invalidate()
        onCancel?()
    }

    private func startCountdown() {
        countdown = timerDelay
        shutterButton.isEnabled = false
        timerSegment.isUserInteractionEnabled = false
        updateCountdownDisplay()

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.countdown -= 1
            if self.countdown <= 0 {
                timer.invalidate()
                self.capturePhoto()
            } else {
                self.updateCountdownDisplay()
            }
        }
    }

    private func updateCountdownDisplay() {
        countdownLabel.text = "\(countdown)"
        countdownLabel.alpha = 1
        countdownLabel.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: []) {
            self.countdownLabel.transform = .identity
        }
    }

    private func capturePhoto() {
        countdownLabel.alpha = 0
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension TimerCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            shutterButton.isEnabled = true
            timerSegment.isUserInteractionEnabled = true
            return
        }

        // Mirror the front camera image (front camera is mirrored by default in preview but not in capture)
        guard let cgImage = image.cgImage else {
            shutterButton.isEnabled = true
            timerSegment.isUserInteractionEnabled = true
            return
        }
        let mirrored = UIImage(cgImage: cgImage, scale: image.scale, orientation: .leftMirrored)

        // Flash feedback
        flashView.alpha = 1
        UIView.animate(withDuration: 0.2) { self.flashView.alpha = 0 }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.showReview(image: mirrored)
        }
    }
}
