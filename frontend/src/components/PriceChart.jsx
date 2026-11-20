import { ComposedChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import { useIsMobile } from '../hooks/useIsMobile'

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const shortDate = (day) => { // 'YYYY-MM-DD' -> 'Oct 23' (string maths: no timezone shift)
  const [, m, d] = String(day).split('-')
  return MONTHS[Number(m) - 1] ? `${MONTHS[Number(m) - 1]} ${Number(d)}` : day
}

export default function PriceChart({ bars, trend, loading }) {
  const isMobile = useIsMobile()
  const sentMap = {}
  for (const pt of (trend?.points || [])) {
    const day = pt.bucket.slice(0, 10)
    sentMap[day] = Number(pt.mean_compound.toFixed(3))
  }

  // Price draws as soon as it arrives. Once the sentiment is in, the chart starts where the sentiment starts, so
  // both lines span the same period (news only reaches back a few weeks, price a year).
  const sentStart = Object.keys(sentMap).sort()[0] ?? null
  const data = (bars || [])
    .map((b) => {
      const day = (b.timestamp || '').slice(0, 10)
      return { day, price: Number(Number(b.close).toFixed(2)), sentiment: sentMap[day] ?? null }
    })
    .filter((d) => !sentStart || d.day >= sentStart)

  const aspect = isMobile ? 1.3 : 2.2
  if (!data.length) {
    return (
      <div className="card">
        <h2 className="card-title">Price and sentiment</h2>
        <div className="chart-empty" style={{ aspectRatio: aspect }} role={loading ? 'progressbar' : undefined} aria-label={loading ? 'Loading price history' : undefined}>
          <span className="muted-text">{loading ? 'Loading price history…' : 'No price history for this ticker.'}</span>
        </div>
      </div>
    )
  }

  const tooltipStyle = {
    contentStyle: {
      background: '#1b1f24',
      border: '1px solid rgba(255,255,255,0.14)',
      borderRadius: 6,
      fontSize: 12,
    },
    labelStyle: { color: '#98a1ab' },
  }

  return (
    <div className="card">
      <h2 className="card-title">Price and sentiment</h2>
      <ResponsiveContainer width="100%" aspect={aspect}>
        <ComposedChart data={data} margin={{ bottom: 8, right: isMobile ? 8 : 48, left: 4 }}>
          <CartesianGrid vertical={false} stroke="rgba(255,255,255,0.06)" />
          <XAxis
            dataKey="day"
            tick={{ fontSize: 10, fill: '#98a1ab' }}
            tickFormatter={shortDate}
            interval="preserveStartEnd"
            minTickGap={isMobile ? 28 : 48}
            height={24}
          />
          <YAxis
            yAxisId="price"
            orientation="right"
            domain={['auto', 'auto']}
            tick={{ fontSize: 10, fill: '#98a1ab' }}
            width={isMobile ? 38 : 52}
            tickFormatter={(v) => `$${Math.round(v)}`}
          />
          <YAxis
            yAxisId="sentiment"
            orientation="left"
            domain={[-1, 1]}
            tick={{ fontSize: 10, fill: '#6ea8fe' }}
            width={isMobile ? 24 : 32}
          />
          <Tooltip {...tooltipStyle} />
          <Legend wrapperStyle={{ fontSize: 11, color: '#98a1ab', paddingTop: 4 }} />
          <Line
            yAxisId="price"
            type="monotone"
            dataKey="price"
            stroke="#e6e8eb"
            dot={false}
            strokeWidth={1.5}
            name="Close Price"
          />
          <Line
            yAxisId="sentiment"
            type="monotone"
            dataKey="sentiment"
            stroke="#6ea8fe"
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
