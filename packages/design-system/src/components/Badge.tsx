import type React from 'react'
import { cx } from '../utils/cx'

export interface BadgeProps {
  children: React.ReactNode
  dot?: boolean
  className?: string
}

export function Badge({
  children,
  dot = true,
  className,
}: BadgeProps): React.JSX.Element {
  return (
    <span className={cx('mw-badge', className)}>
      {dot && <span className="mw-badge__dot" />}
      {children}
    </span>
  )
}
