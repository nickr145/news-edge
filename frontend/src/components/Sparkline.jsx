export default function Sparkline({ closes, width = 96, height = 26 }) {
  if (!closes || closes.length < 2) return <span className="flat">–</span>
  const min = Math.min(...closes)
  const span = Math.max(...closes) - min || 1
  const points = closes
    .map((c, i) => `${((i / (closes.length - 1)) * width).toFixed(1)},${(height - 2 - ((c - min) / span) * (height - 4)).toFixed(1)}`)
    .join(' ')
  const rising = closes[closes.length - 1] >= closes[0]
  return (
    <svg className="spark" width={width} height={height} viewBox={`0 0 ${width} ${height}`} aria-hidden="true">
      <polyline points={points} fill="none" stroke={rising ? '#10b981' : '#ef4444'} strokeWidth="1.5" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  )
}
