import type React from 'react'
import { Card, type CardTone } from './Card'

export interface StatCardProps {
  value: React.ReactNode
  label: React.ReactNode
  footnote?: React.ReactNode
  tone?: CardTone
  wide?: boolean
  className?: string
}

export function StatCard({
  value,
  label,
  footnote,
  tone = 'c1',
  wide,
  className,
}: StatCardProps): React.JSX.Element {
  return (
    <Card tone={tone} wide={wide} className={className}>
      <div className="mw-stat__value">{value}</div>
      <p className="mw-stat__label">{label}</p>
      {footnote && <p className="mw-stat__foot">{footnote}</p>}
    </Card>
  )
}
