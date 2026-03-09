import { BarChart, Bar, LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'

export default function SentimentPanel({ summary, trend }) {
  const barData = Object.entries(summary?.label_distribution || {}).map(([label, value]) => ({ label, value }))
  const trendData = (trend?.points || []).map((p) => ({
    time: new Date(p.bucket).toLocaleDateString(),
    score: Number(p.mean_compound.toFixed(3))
  }))

  return (
    <section className="card">
      <h2>Sentiment</h2>
      <div className="metrics-row">
        <div><small>EWMA</small><strong>{summary?.ewma_compound?.toFixed?.(3) ?? '0.000'}</strong></div>
        <div><small>Mean</small><strong>{summary?.mean_compound?.toFixed?.(3) ?? '0.000'}</strong></div>
        <div><small>Std</small><strong>{summary?.std_compound?.toFixed?.(3) ?? '0.000'}</strong></div>
        <div><small>Articles</small><strong>{summary?.count ?? 0}</strong></div>
      </div>
      <div className="charts-grid">
        <div className="chart-wrap">
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={trendData}>
              <XAxis dataKey="time" hide />
              <YAxis domain={[-1, 1]} />
              <Tooltip />
              <Line type="monotone" dataKey="score" stroke="#00e5a8" dot={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>
        <div className="chart-wrap">
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={barData}>
              <XAxis dataKey="label" />
              <YAxis />
              <Tooltip />
              <Bar dataKey="value" fill="#ffb703" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
    </section>
  )
}
