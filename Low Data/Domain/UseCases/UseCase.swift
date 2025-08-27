//
//  UseCase.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Base protocol for all use cases
public protocol UseCase {
    associatedtype Input
    associatedtype Output
    
    func execute(_ input: Input) async throws -> Output
}

/// Use case that doesn't require input
public protocol NoInputUseCase {
    associatedtype Output
    
    func execute() async throws -> Output
}

/// Use case that doesn't return output
public protocol NoOutputUseCase {
    associatedtype Input
    
    func execute(_ input: Input) async throws
}

/// Use case for observing/streaming data
public protocol ObservableUseCase {
    associatedtype Input
    associatedtype Output
    
    func observe(_ input: Input) -> AsyncThrowingStream<Output, Error>
}

/// Result wrapper for use cases that can partially succeed
public enum UseCaseResult<Success, Failure: Error> {
    case success(Success)
    case failure(Failure)
    case partial(Success, [Failure])
}

/// Common errors for use cases
public enum UseCaseError: LocalizedError {
    case invalidInput(String)
    case dependencyNotAvailable(String)
    case operationCancelled
    case unauthorized
    case networkUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .dependencyNotAvailable(let dependency):
            return "Required dependency not available: \(dependency)"
        case .operationCancelled:
            return "Operation was cancelled"
        case .unauthorized:
            return "Unauthorized to perform this operation"
        case .networkUnavailable:
            return "Network is not available"
        }
    }
}