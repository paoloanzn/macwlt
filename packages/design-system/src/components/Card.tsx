import type React from 'react'
import { cx } from '../utils/cx'

export type CardTone = 'surface' | 'accent' | 'c1' | 'c2' | 'c3' | 'c4'

export interface BentoProps {
  children: React.ReactNode
  className?: string
}

export function Bento({
  children,
  className,
}: BentoProps): React.JSX.Element {
  return <div className={cx('mw-bento', className)}>{children}</div>
}

export interface CardProps {
  tone?: CardTone
  wide?: boolean
  tall?: boolean
  children: React.ReactNode
  className?: string
  style?: React.CSSProperties
  id?: string
}

export function Card({
  tone = 'surface',
  wide,
  tall = true,
  children,
  className,
  style,
  id,
}: CardProps): React.JSX.Element {
  return (
    <article
      id={id}
      className={cx(
        'mw-card',
        `mw-card--${tone}`,
        tall && 'mw-card--tall',
        wide && 'mw-card--span2',
        className,
      )}
      style={style}
    >
      {children}
    </article>
  )
}

export interface CardBadgeProps {
  children: React.ReactNode
  className?: string
}

export function CardBadge({
  children,
  className,
}: CardBadgeProps): React.JSX.Element {
  return <div className={cx('mw-card__badge', className)}>{children}</div>
}
