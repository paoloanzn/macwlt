import type React from 'react'
import { cx } from '../utils/cx'

export type BandTone = 'dark' | 'accent' | 'c1' | 'c2'

export interface BandCardProps {
  tone?: BandTone
  title: React.ReactNode
  body?: React.ReactNode
  icon?: React.ReactNode
  onClick?: () => void
  className?: string
}

export function BandCard({
  tone = 'dark',
  title,
  body,
  icon,
  onClick,
  className,
}: BandCardProps): React.JSX.Element {
  return (
    <div
      className={cx('mw-band', `mw-band--${tone}`, className)}
      onClick={onClick}
    >
      <div className="mw-band__title">{title}</div>
      {body && <div className="mw-band__body">{body}</div>}
      {icon && <div className="mw-band__icon">{icon}</div>}
    </div>
  )
}
