import type React from 'react'
import { cx } from '../utils/cx'

export interface MarqueeProps {
  text: string
  repeat?: number
  separator?: string
  className?: string
}

export function Marquee({
  text,
  repeat = 2,
  separator = ' · ',
  className,
}: MarqueeProps): React.JSX.Element {
  const phrase = `${Array.from({ length: repeat }, () => text).join(separator)}${separator}`

  return (
    <div className={cx('mw-marquee', className)}>
      <div className="mw-marquee__track">{phrase}</div>
    </div>
  )
}
