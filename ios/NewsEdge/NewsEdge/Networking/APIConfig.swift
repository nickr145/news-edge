import Foundation

enum APIConfig {
    // FastAPI backend deployed on Railway (RAILWAY_PUBLIC_DOMAIN); the Vercel
    // deployment at news-edge-ai.vercel.app only serves the React frontend build.
    // DEBUG and RELEASE both point here so the simulator always shows real data;
    // DEBUG builds hitting an isolated local `uvicorn` would need their own backfill
    // to have anything to show, which isn't worth the tradeoff.
    static var baseURL: URL {
        URL(string: "https://news-edge-production.up.railway.app")!
    }

    static var webSocketBaseURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        return components.url!
    }
}
