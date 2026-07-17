import type React from 'react'
import { cx } from '../utils/cx'

export interface WordmarkProps {
  size?: number
  className?: string
  style?: React.CSSProperties
}

export function Wordmark({
  size = 26,
  className,
  style,
}: WordmarkProps): React.JSX.Element {
  return (
    <span
      className={cx('mw-wordmark', className)}
      style={{ fontSize: size, ...style }}
    >
      <img
        className="mw-wordmark__logo"
        src="/macwlt-logo.svg"
        alt=""
        aria-hidden="true"
      />
      <span className="mw-wordmark__mac">mac</span>
      <span className="mw-wordmark__wlt">wlt</span>
    </span>
  )
}
