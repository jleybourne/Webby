//
//  CursorView.swift
//  Webby
//
//  An iPadOS-style adaptive pointer: a soft disc that grows and tints when it
//  hovers over something clickable.
//

import UIKit

final class CursorView: UIView {

    static let size: CGFloat = 34

    private let disc = UIView()
    private let ring = UIView()

    var isHoveringInteractive = false {
        didSet {
            guard oldValue != isHoveringInteractive else { return }
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.applyState()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size * 2, height: Self.size * 2))
        isUserInteractionEnabled = false

        ring.frame = bounds
        ring.layer.cornerRadius = bounds.width / 2
        ring.layer.borderWidth = 3
        ring.layer.borderColor = UIColor.systemBlue.cgColor
        ring.alpha = 0
        addSubview(ring)

        disc.bounds = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        disc.center = CGPoint(x: bounds.midX, y: bounds.midY)
        disc.layer.cornerRadius = Self.size / 2
        disc.backgroundColor = UIColor(white: 0.15, alpha: 0.55)
        disc.layer.borderColor = UIColor.white.cgColor
        disc.layer.borderWidth = 3
        disc.layer.shadowColor = UIColor.black.cgColor
        disc.layer.shadowOpacity = 0.45
        disc.layer.shadowRadius = 8
        disc.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(disc)
        applyState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The point the cursor is aiming at, in its superview's coordinates.
    var hotspot: CGPoint {
        get { center }
        set { center = newValue }
    }

    func pulse() {
        UIView.animate(withDuration: 0.08, animations: {
            self.disc.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        }, completion: { _ in
            UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.5,
                           initialSpringVelocity: 0.8, options: [.allowUserInteraction]) {
                self.applyState()
            }
        })
    }

    private func applyState() {
        if isHoveringInteractive {
            disc.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
            disc.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.55)
            ring.alpha = 0.9
            ring.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        } else {
            disc.transform = .identity
            disc.backgroundColor = UIColor(white: 0.15, alpha: 0.55)
            ring.alpha = 0
            ring.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
    }
}

/// Floating capsule at the top of the screen: security, host, blocked count and input mode.
final class StatusHUDView: UIView {

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let stack = UIStackView()
    private let lockIcon = UIImageView()
    private let hostLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let shieldIcon = UIImageView()
    private let blockedLabel = UILabel()
    private let modeLabel = UILabel()
    private var hideWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 30
        layer.cornerCurve = .continuous
        clipsToBounds = true

        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        lockIcon.preferredSymbolConfiguration = symbolConfig
        lockIcon.tintColor = .white
        shieldIcon.preferredSymbolConfiguration = symbolConfig
        shieldIcon.image = UIImage(systemName: "shield.fill")
        shieldIcon.tintColor = .systemGreen

        for label in [hostLabel, blockedLabel, modeLabel] {
            label.textColor = .white
            label.font = .systemFont(ofSize: 26, weight: .semibold)
        }
        modeLabel.textColor = UIColor(white: 1, alpha: 0.7)
        modeLabel.font = .systemFont(ofSize: 22, weight: .medium)
        spinner.color = .white
        spinner.hidesWhenStopped = true

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        [lockIcon, hostLabel, spinner, shieldIcon, blockedLabel, modeLabel].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(26, after: spinner)
        stack.setCustomSpacing(6, after: shieldIcon)
        stack.setCustomSpacing(26, after: blockedLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(equalToConstant: 60),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(url: URL?, isLoading: Bool, blocked: Int, mode: String) {
        let secure = url?.scheme == "https"
        lockIcon.image = UIImage(systemName: secure ? "lock.fill" : "globe")
        lockIcon.tintColor = secure ? .white : UIColor(white: 1, alpha: 0.7)
        hostLabel.text = url.map { URLResolver.displayHost($0) } ?? "Webby"
        if isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
        shieldIcon.isHidden = blocked == 0
        blockedLabel.isHidden = blocked == 0
        blockedLabel.text = "\(blocked)"
        modeLabel.text = mode
    }

    func flash(for duration: TimeInterval = 3.0, keepVisible: Bool = false) {
        hideWorkItem?.cancel()
        UIView.animate(withDuration: 0.25) { self.alpha = 1 }
        guard !keepVisible else { return }
        let item = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.5) { self?.alpha = 0 }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }
}

/// Transient centered message ("Scroll mode", "Bookmarked", …).
final class ToastView: UIView {
    private let label = UILabel()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private var hideWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 30, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        addSubview(blur)
        addSubview(label)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            widthAnchor.constraint(lessThanOrEqualToConstant: 1100),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ text: String, duration: TimeInterval = 1.6) {
        label.text = text
        hideWorkItem?.cancel()
        transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            self.alpha = 1
            self.transform = .identity
        }
        let item = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.4) { self?.alpha = 0 }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }
}
