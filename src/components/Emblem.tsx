// A 24-spoke ring evoking a job-card seal. Inline SVG, inherits currentColor.
// Deliberately not the official State Emblem (legal) — a generic civic mark.
export function Emblem({ size = 28 }: { size?: number }) {
  const spokes = Array.from({ length: 24 })
  return (
    <svg width={size} height={size} viewBox="0 0 48 48" role="img" aria-label="LabourPass seal" fill="none">
      <circle cx="24" cy="24" r="21" stroke="currentColor" strokeWidth="2.5" />
      <circle cx="24" cy="24" r="4" fill="currentColor" />
      {spokes.map((_, i) => {
        const a = (i * 15 * Math.PI) / 180
        return (
          <line
            key={i}
            x1={24 + 5 * Math.cos(a)}
            y1={24 + 5 * Math.sin(a)}
            x2={24 + 19 * Math.cos(a)}
            y2={24 + 19 * Math.sin(a)}
            stroke="currentColor"
            strokeWidth="1"
            opacity="0.85"
          />
        )
      })}
    </svg>
  )
}
