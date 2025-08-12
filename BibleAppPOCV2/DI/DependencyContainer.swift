// filepath: BibleAppPOCV2/DI/DependencyContainer.swift
//
//  DependencyContainer.swift
//  BibleAppPOCV2
//
//  Created by Architecture Review on 7/9/25.
//

import Foundation
import SwiftUI

// MARK: - Simple Dependency Injection Container

final class DIContainer {
    static let shared = DIContainer()
    
    private var factories: [String: () -> Any] = [:]
    private var singletons: [String: Any] = [:]
    
    private init() {}
    
    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        factories[key] = factory
    }
    
    func registerSingleton<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        factories[key] = factory
    }
    
    func resolve<T>(_ type: T.Type) -> T {
        let key = String(describing: type)
        
        // Check if it's a singleton first
        if let singleton = singletons[key] as? T {
            return singleton
        }
        
        // Create new instance
        guard let factory = factories[key] else {
            fatalError("No factory registered for type \(type)")
        }
        
        guard let instance = factory() as? T else {
            fatalError("Factory for type \(type) returned wrong type")
        }
        
        // Store as singleton if factory was registered as singleton
        singletons[key] = instance
        
        return instance
    }
}

// MARK: - SwiftUI Environment Integration

struct DIContainerKey: EnvironmentKey {
    static let defaultValue: DIContainer = DIContainer.shared
}

extension EnvironmentValues {
    var diContainer: DIContainer {
        get { self[DIContainerKey.self] }
        set { self[DIContainerKey.self] = newValue }
    }
}

// MARK: - View Modifier for DI

struct WithDependencies: ViewModifier {
    let container: DIContainer
    
    func body(content: Content) -> some View {
        content
            .environment(\.diContainer, container)
    }
}

extension View {
    func withDependencies(_ container: DIContainer = .shared) -> some View {
        modifier(WithDependencies(container: container))
    }
}
