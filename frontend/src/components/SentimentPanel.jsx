import { BarChart, Bar, LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'

export default function SentimentPanel({ summary, trend }) {
  const barData = Object.entries(summary?.label_distribution || {}).map(([label, value]) => ({ label, value }))
  const trendData = (trend?.points || []).map((p) => ({
    time: new Date(p.bucket).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    score: Number(p.mean_compound.toFixed(3))
  }))

  const tooltipStyle = {
    contentStyle: { background: 'rgba(8,15,33,0.97)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8, fontSize: 12 },
    labelStyle: { color: '#64748b' },
    itemStyle: { color: '#10d9a0' }
  }

  return (
    <div className="card">
      <div className="panel-label">Sentiment</div>
      <div className="sentiment-stats">
        <div className="metric-cell">
          <span className="metric-label">EWMA</span>
          <span className="metric-value">{summary?.ewma_compound?.toFixed?.(3) ?? '0.000'}</span>
        </div>
        <div className="metric-cell">
          <span className="metric-label">Mean</span>
          <span className="metric-value">{summary?.mean_compound?.toFixed?.(3) ?? '0.000'}</span>
        </div>
        <div className="metric-cell">
          <span className="metric-label">Std Dev</span>
          <span className="metric-value">{summary?.std_compound?.toFixed?.(3) ?? '0.000'}</span>
        </div>
        <div className="metric-cell">
          <span className="metric-label">Articles</span>
          <span className="metric-value">{summary?.count ?? 0}</span>
        </div>
      </div>
      <div className="charts-grid">
        <div>
          <p className="chart-label">Sentiment Trend</p>
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={trendData} margin={{ bottom: 20, right: 4 }}>
              <XAxis
                dataKey="time"
                tick={{ fontSize: 10, fill: '#64748b' }}
                interval="preserveStartEnd"
                angle={-30}
                textAnchor="end"
                height={40}
              />
              <YAxis domain={[-1, 1]} tick={{ fontSize: 10, fill: '#64748b' }} width={32} />
              <Tooltip {...tooltipStyle} />
              <ReferenceLine y={0} stroke="rgba(255,255,255,0.12)" strokeDasharray="3 3" />
              <Line type="monotone" dataKey="score" stroke="#10d9a0" dot={false} strokeWidth={2} />
            </LineChart>
          </ResponsiveContainer>
        </div>
        <div>
          <p className="chart-label">Label Distribution</p>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={barData} margin={{ bottom: 4, right: 4 }}>
              <XAxis dataKey="label" tick={{ fontSize: 11, fill: '#64748b' }} />
              <YAxis tick={{ fontSize: 10, fill: '#64748b' }} width={32} />
              <Tooltip {...{ ...tooltipStyle, itemStyle: { color: '#fbbf24' } }} />
              <Bar dataKey="value" fill="#fbbf24" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  )
}
