import { BarChart, Bar, Cell, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'
import { useIsMobile } from '../hooks/useIsMobile'

const LABEL_COLORS = { POSITIVE: '#10b981', NEUTRAL: '#f59e0b', NEGATIVE: '#ef4444' }

export default function SentimentPanel({ summary, trend }) {
  const isMobile = useIsMobile()
  const barData = Object.entries(summary?.label_distribution || {}).map(([label, value]) => ({ label, value }))
  const trendData = (trend?.points || []).map((p) => ({
    time: new Date(p.bucket).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    score: Number(p.mean_compound.toFixed(3))
  }))

  const tooltipStyle = {
    contentStyle: { background: '#1b1f24', border: '1px solid rgba(255,255,255,0.14)', borderRadius: 6, fontSize: 12 },
    labelStyle: { color: '#98a1ab' },
    itemStyle: { color: '#6ea8fe' }
  }

  return (
    <div className="card">
      <h2 className="card-title">Sentiment</h2>
      <div className="stat-row">
        <div className="stat">
          <span className="stat-label">EWMA</span>
          <span className="stat-value">{summary?.ewma_compound?.toFixed?.(3) ?? '0.000'}</span>
        </div>
        <div className="stat">
          <span className="stat-label">Mean</span>
          <span className="stat-value">{summary?.mean_compound?.toFixed?.(3) ?? '0.000'}</span>
        </div>
        <div className="stat">
          <span className="stat-label">Std dev</span>
          <span className="stat-value">{summary?.std_compound?.toFixed?.(3) ?? '0.000'}</span>
        </div>
        <div className="stat">
          <span className="stat-label" title="Distinct events: the same story from several outlets counts once">Stories</span>
          <span className="stat-value">{summary?.count ?? 0}</span>
        </div>
      </div>
      <div className="charts-grid">
        <div>
          <p className="chart-title">Sentiment trend</p>
          <ResponsiveContainer width="100%" aspect={isMobile ? 1.4 : 2.4}>
            <LineChart data={trendData} margin={{ bottom: 20, right: 4 }}>
              <CartesianGrid vertical={false} stroke="rgba(255,255,255,0.06)" />
              <XAxis
                dataKey="time"
                tick={{ fontSize: 10, fill: '#98a1ab' }}
                interval="preserveStartEnd"
                angle={isMobile ? 0 : -30}
                textAnchor={isMobile ? 'middle' : 'end'}
                height={isMobile ? 24 : 40}
              />
              <YAxis domain={[-1, 1]} tick={{ fontSize: 10, fill: '#98a1ab' }} width={isMobile ? 26 : 32} />
              <Tooltip {...tooltipStyle} />
              <ReferenceLine y={0} stroke="rgba(255,255,255,0.18)" strokeDasharray="3 3" />
              <Line type="monotone" dataKey="score" stroke="#6ea8fe" dot={false} strokeWidth={2} />
            </LineChart>
          </ResponsiveContainer>
        </div>
        <div>
          <p className="chart-title">Label distribution</p>
          <ResponsiveContainer width="100%" aspect={isMobile ? 1.4 : 2.4}>
            <BarChart data={barData} margin={{ bottom: 4, right: 4 }}>
              <CartesianGrid vertical={false} stroke="rgba(255,255,255,0.06)" />
              <XAxis dataKey="label" tick={{ fontSize: isMobile ? 9 : 11, fill: '#98a1ab' }} />
              <YAxis tick={{ fontSize: 10, fill: '#98a1ab' }} width={isMobile ? 26 : 32} />
              <Tooltip {...{ ...tooltipStyle, itemStyle: { color: '#e6e8eb' } }} />
              <Bar dataKey="value" radius={[4, 4, 0, 0]}>
                {barData.map((d) => <Cell key={d.label} fill={LABEL_COLORS[d.label] || '#98a1ab'} />)}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  )
}
