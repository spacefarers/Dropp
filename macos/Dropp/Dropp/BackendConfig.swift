// BackendConfig.swift
import Foundation

enum Backend {
    static let baseURL = URL(string: "https://dropp.yangm.tech")!
//    static let baseURL = URL(string: "http://localhost:3000")!
    static let loginURL = baseURL.appendingPathComponent("login")
    static let apiBaseURL = baseURL.appendingPathComponent("api")
}
