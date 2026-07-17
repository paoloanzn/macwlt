import type React from 'react'
import { cx } from '../utils/cx'

export interface HeroProps {
  badge?: React.ReactNode
  title: React.ReactNode
  subtitle?: React.ReactNode
  actions?: React.ReactNode
  visual?: React.ReactNode
  className?: string
}

export function Hero({
  badge,
  title,
  subtitle,
  actions,
  visual,
  className,
}: HeroProps): React.JSX.Element {
  return (
    <section id="top" className={cx('mw-hero', className)}>
      {badge && <div className="mw-hero__badge">{badge}</div>}
      <h1 className="mw-display mw-display--xl mw-hero__title">{title}</h1>
      {subtitle && <p className="mw-hero__sub">{subtitle}</p>}
      {actions && <div className="mw-hero__actions">{actions}</div>}
      {visual && (
        <div className="mw-hero__visual">
          <div className="mw-hero__frame">{visual}</div>
        </div>
      )}
    </section>
  )
}
