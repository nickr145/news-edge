import { Link, Route, Routes } from 'react-router-dom'
import SearchPage from './pages/SearchPage'
import TickerPage from './pages/TickerPage'

export default function App() {
  return (
    <>
      <header className="topbar">
        <Link to="/" className="nav-brand">
          <div className="nav-mark">NE</div>
          <span className="nav-name">NewsEdge</span>
        </Link>
        <nav className="nav-links">
          <Link to="/">Search</Link>
        </nav>
      </header>
      <div className="app-content">
        <Routes>
          <Route path="/" element={<SearchPage />} />
          <Route path="/ticker/:symbol" element={<TickerPage />} />
        </Routes>
      </div>
    </>
  )
}
