import Foundation

enum APIConfig {
    /// Simulator/device debug builds talk to a locally running `uvicorn` (see handoff brief).
    /// Loopback addresses are exempt from App Transport Security, so no Info.plist
    /// exception is needed for this to work in the simulator.
    static var baseURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:8000")!
        #else
        // FastAPI backend deployed on Railway (RAILWAY_PUBLIC_DOMAIN); the Vercel
        // deployment at news-edge-ai.vercel.app only serves the React frontend build.
        return URL(string: "https://news-edge-production.up.railway.app")!
        #endif
    }

    static var webSocketBaseURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        return components.url!
    }
}
