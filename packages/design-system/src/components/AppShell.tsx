import type React from 'react'
import { cx } from '../utils/cx'

export interface AppShellProps {
  children: React.ReactNode
  className?: string
  style?: React.CSSProperties
}

export function AppShell({
  children,
  className,
  style,
}: AppShellProps): React.JSX.Element {
  return (
    <div className={cx('mw-app', className)} style={style}>
      {children}
    </div>
  )
}
