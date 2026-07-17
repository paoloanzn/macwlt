import type React from 'react'
import { cx } from '../utils/cx'

export interface SectionProps {
  children: React.ReactNode
  contained?: boolean
  id?: string
  className?: string
  style?: React.CSSProperties
}

export function Section({
  children,
  contained = true,
  id,
  className,
  style,
}: SectionProps): React.JSX.Element {
  return (
    <section id={id} className={cx('mw-section', className)} style={style}>
      {contained ? <div className="mw-container">{children}</div> : children}
    </section>
  )
}
