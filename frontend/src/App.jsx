import { Link, Route, Routes, useLocation } from 'react-router-dom'
import SearchPage from './pages/SearchPage'
import TickerPage from './pages/TickerPage'
import TickerSearch from './components/TickerSearch'

export default function App() {
  const location = useLocation()
  const onHome = location.pathname === '/'

  return (
    <>
      <header className="topbar">
        <Link to="/" className="nav-brand">
          <div className="nav-mark">NE</div>
          <span className="nav-name">NewsEdge</span>
        </Link>
        {!onHome && <TickerSearch compact />}
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
