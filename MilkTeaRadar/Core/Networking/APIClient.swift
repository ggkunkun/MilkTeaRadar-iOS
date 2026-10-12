//
//  APIClient.swift
//  MilkTeaRadar
//
//  统一网络层：所有 REST 请求都走这里。
//  保证三件事：
//    1) 超时可控（默认 8 秒，见 Config.requestTimeout）；
//    2) 自动重试：仅对「超时 / 断网 / 5xx / 429」重试，指数退避 + 抖动，最多 3 次；
//       4xx 业务错误不重试（重试也没用，只会拖慢错误反馈）；
//    3) 错误可操作：统一 NetworkError，UI 层据此给出明确动作。
//

import Foundation

// MARK: - 错误定义

enum NetworkError: Error, LocalizedError {
    case timeout
    case offline
    case http(status: Int)
    case decode
    case invalidURL

    /// 是否值得重试
    var isRetryable: Bool {
        switch self {
        case .timeout, .offline:      return true
        case .http(let s):            return s >= 500 || s == 429
        case .decode, .invalidURL:    return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .timeout:          return "请求超时"
        case .offline:          return "网络不可用"
        case .http(let s):      return "服务端返回 \(s)"
        case .decode:           return "数据解析失败"
        case .invalidURL:       return "地址无效"
        }
    }

    /// 给用户的可操作建议
    var recoveryHint: String {
        switch self {
        case .timeout:   return "已自动重试 3 次仍未成功。建议切换到更稳定的网络后重试。"
        case .offline: return "当前处于离线状态，正在显示本地缓存数据。联网后会自动同步。"
        case .http(let s) where s >= 500:
                        return "服务端暂时不可用，请稍后重试。"
        case .http(429):return "请求过于频繁，已自动退避等待后重试。"
        case .decode:   return "云端数据格式异常，已回退到本地缓存。"
        default:        return "请稍后重试。"
        }
    }
}

// MARK: - 客户端

actor APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = Config.requestTimeout
        cfg.timeoutIntervalForResource = Config.requestTimeout * 2
        cfg.waitsForConnectivity = false      // 快速失败，交由重试逻辑处理
        cfg.urlCache = nil                    // 绕过 NSURLCache，避免拿到陈旧响应
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: cfg)
        self.decoder = JSONDecoder()
    }

    /// 拉取最新优惠文档（含自动重试）
    /// - Returns: DealsDocument
    /// - Throws: NetworkError
    func fetchDeals() async throws -> DealsDocument {
        var lastError: NetworkError = .invalidURL

        for attempt in 0...Config.maxRetries {
            do {
                var comps = URLComponents(string: Config.apiBaseURL + Config.dealsPath)
                comps?.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
                guard let url = comps?.url else { throw NetworkError.invalidURL }

                var req = URLRequest(url: url)
                req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                req.timeoutInterval = Config.requestTimeout

                let (data, resp) = try await session.data(for: req)

                guard let http = resp as? HTTPURLResponse else { throw NetworkError.decode }
                guard (200..<300).contains(http.statusCode) else {
                    throw NetworkError.http(status: http.statusCode)
                }

                do {
                    return try decoder.decode(DealsDocument.self, from: data)
                } catch {
                    throw NetworkError.decode
                }

            } catch let e as NetworkError {
                lastError = e
                if !e.isRetryable { throw e }
                if attempt < Config.maxRetries {
                    try? await Task.sleep(nanoseconds: backoff(attempt))
                    continue
                }
                throw e
            } catch {
                // URLSession 抛出的 URLError
                let mapped = NetworkError.map(error)
                lastError = mapped
                if !mapped.isRetryable { throw mapped }
                if attempt < Config.maxRetries {
                    try? await Task.sleep(nanoseconds: backoff(attempt))
                    continue
                }
                throw mapped
            }
        }

        throw lastError
    }

    /// 指数退避：base * 2^attempt，带 0~30% 抖动，上限 backoffMax
    private func backoff(_ attempt: Int) -> UInt64 {
        let d = min(Config.backoffBase * pow(2.0, Double(attempt)), Config.backoffMax)
        let jittered = d * (1 + Double.random(in: 0...0.3))
        return UInt64(jittered * 1_000_000_000)
    }
}

// MARK: - URLError 映射

extension NetworkError {
    static func map(_ error: Error) -> NetworkError {
        let e = error as NSError
        if e.domain == NSURLErrorDomain {
            switch e.code {
            case NSURLErrorTimedOut:                    return .timeout
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:              return .offline
            default:                                     return .offline
            }
        }
        if error is DecodingError { return .decode }
        return .offline
    }
}
