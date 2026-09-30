//
//  LiquidGlassObserver.swift
//  AIUsage
//  Observes the system "Liquid Glass" intensity set in System Settings > Appearance
//  and publishes it so the whole SwiftUI hierarchy can adapt in real time.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Liquid Glass System Preference Observer

/// Reads the macOS system Liquid Glass setting from `NSGlassTintAmount`
/// (the key written by System Settings > Appearance > Liquid Glass slider).
///
/// - `tintAmount`: Raw slider value (0.0 – 1.0). `0` = slider dialed to minimum;
///   values approaching `1` = maximum Liquid Glass tinting.
/// - `isEnabled`: Convenience bool — `true` when tintAmount > 0.05.
/// - `intensity`: Same as tintAmount clamped to 0…1, ready to multiply opacities.
public final class LiquidGlassObserver: ObservableObject {

    /// Singleton — created once on app startup.
    public static let shared = LiquidGlassObserver()

    // System Liquid Glass slider value (0.0 = off … 1.0 = full)
    @Published public private(set) var tintAmount: Double = 0.5

    // Convenience: glass is meaningfully on
    public var isEnabled: Bool { tintAmount > 0.05 }

    // Derived opacity multiplier (0.0 – 1.0) for glass layers
    public var intensity: Double { max(0, min(1, tintAmount)) }

    private let defaults = UserDefaults.standard
    private var observation: NSKeyValueObservation?
    private var notificationObserver: Any?

    private init() {
        readCurrentValue()
        startObserving()
    }

    // MARK: - Private

    private func readCurrentValue() {
        // NSGlassTintAmount is stored in the global domain by System Settings.
        // When the key has never been written, defaults.double() returns 0.0 —
        // we treat "key missing" as the system default (≈ 0.5 = partially enabled).
        let raw = defaults.double(forKey: "NSGlassTintAmount")
        let value: Double = (defaults.object(forKey: "NSGlassTintAmount") == nil) ? 0.5 : raw
        DispatchQueue.main.async { [weak self] in
            self?.tintAmount = value
        }
    }

    private func startObserving() {
        // KVO: fires immediately with the current value and on every in-process change.
        observation = defaults.observe(\.NSGlassTintAmount, options: [.new, .initial]) { [weak self] _, change in
            guard let self, let newValue = change.newValue else { return }
            DispatchQueue.main.async {
                self.tintAmount = newValue
            }
        }

        // DidChangeNotification: catches cross-process writes from System Settings
        // which sometimes don't fire KVO on the UserDefaults.standard domain.
        notificationObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            self?.readCurrentValue()
        }
    }

    deinit {
        observation?.invalidate()
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

// MARK: - UserDefaults KVO helper

extension UserDefaults {
    /// Exposes `NSGlassTintAmount` as an `@objc dynamic` property for KVO.
    @objc dynamic var NSGlassTintAmount: Double {
        return double(forKey: "NSGlassTintAmount")
    }
}

// MARK: - SwiftUI Environment Key

private struct LiquidGlassObserverKey: EnvironmentKey {
    static var defaultValue: LiquidGlassObserver { .shared }
}

public extension EnvironmentValues {
    var liquidGlassObserver: LiquidGlassObserver {
        get { self[LiquidGlassObserverKey.self] }
        set { self[LiquidGlassObserverKey.self] = newValue }
    }
}
