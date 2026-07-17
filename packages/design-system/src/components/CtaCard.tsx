import type React from 'react'
import { Card, type CardTone } from './Card'

export interface CtaCardProps {
  title: React.ReactNode
  action?: React.ReactNode
  note?: React.ReactNode
  tone?: CardTone
  wide?: boolean
  id?: string
  className?: string
}

export function CtaCard({
  title,
  action,
  note,
  tone = 'c4',
  wide = true,
  id,
  className,
}: CtaCardProps): React.JSX.Element {
  return (
    <Card
      tone={tone}
      wide={wide}
      id={id}
      className={className}
    >
      <div className="mw-cta-card">
        <div className="mw-cta-card__title">{title}</div>
        {action}
        {note && <p className="mw-cta-card__note">{note}</p>}
      </div>
    </Card>
  )
}
