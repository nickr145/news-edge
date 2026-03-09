import { Link, Route, Routes } from 'react-router-dom'
import SearchPage from './pages/SearchPage'
import TickerPage from './pages/TickerPage'

export default function App() {
  return (
    <div className="app-shell">
      <header className="topbar">
        <h1>NewsEdge</h1>
        <nav>
          <Link to="/">Search</Link>
        </nav>
      </header>
      <main className="layout">
        <Routes>
          <Route path="/" element={<SearchPage />} />
          <Route path="/ticker/:symbol" element={<TickerPage />} />
        </Routes>
      </main>
    </div>
  )
}
