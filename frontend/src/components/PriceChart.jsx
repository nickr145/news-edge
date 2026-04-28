import { ComposedChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts'

export default function PriceChart({ bars, trend }) {
  const sentMap = {}
  for (const pt of (trend?.points || [])) {
    const day = pt.bucket.slice(0, 10)
    sentMap[day] = Number(pt.mean_compound.toFixed(3))
  }

  const sentDates = Object.keys(sentMap).sort()
  const sentStart = sentDates[0] ?? null

  const data = (bars || [])
    .filter((b) => !sentStart || (b.timestamp || '').slice(0, 10) >= sentStart)
    .map((b) => {
      const day = (b.timestamp || '').slice(0, 10)
      return {
        day,
        price: Number(Number(b.close).toFixed(2)),
        sentiment: sentMap[day] ?? null,
      }
    })

  if (!data.length) return null

  const tooltipStyle = {
    contentStyle: {
      background: 'rgba(8,15,33,0.97)',
      border: '1px solid rgba(255,255,255,0.1)',
      borderRadius: 8,
      fontSize: 12,
    },
    labelStyle: { color: '#64748b' },
  }

  return (
    <div className="card">
      <div className="panel-label">Price & Sentiment</div>
      <ResponsiveContainer width="100%" height={240}>
        <ComposedChart data={data} margin={{ bottom: 20, right: 48, left: 4 }}>
          <XAxis
            dataKey="day"
            tick={{ fontSize: 10, fill: '#64748b' }}
            interval="preserveStartEnd"
            angle={-30}
            textAnchor="end"
            height={40}
          />
          <YAxis
            yAxisId="price"
            orientation="right"
            tick={{ fontSize: 10, fill: '#94a3b8' }}
            width={52}
            tickFormatter={(v) => `$${v}`}
          />
          <YAxis
            yAxisId="sentiment"
            orientation="left"
            domain={[-1, 1]}
            tick={{ fontSize: 10, fill: '#10d9a0' }}
            width={32}
          />
          <Tooltip {...tooltipStyle} />
          <Legend wrapperStyle={{ fontSize: 11, color: '#64748b', paddingTop: 4 }} />
          <Line
            yAxisId="price"
            type="monotone"
            dataKey="price"
            stroke="#94a3b8"
            dot={false}
            strokeWidth={1.5}
            name="Close Price"
          />
          <Line
            yAxisId="sentiment"
            type="monotone"
            dataKey="sentiment"
            stroke="#10d9a0"
            dot={false}
            strokeWidth={1.5}
            connectNulls={true}
            name="Sentiment"
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  )
}
