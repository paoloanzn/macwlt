import type React from 'react'
import { cx } from '../utils/cx'

export type ButtonVariant = 'primary' | 'dark' | 'accent' | 'text'
export type ButtonSize = 'sm' | 'md' | 'lg'

interface ButtonCommonProps {
  variant?: ButtonVariant
  size?: ButtonSize
  className?: string
  children: React.ReactNode
}

export type ButtonProps =
  | (ButtonCommonProps &
      { href: string } &
      React.AnchorHTMLAttributes<HTMLAnchorElement>)
  | (ButtonCommonProps &
      { href?: undefined } &
      React.ButtonHTMLAttributes<HTMLButtonElement>)

export function Button(props: ButtonProps): React.JSX.Element {
  if ('href' in props && props.href !== undefined) {
    const {
      variant = 'primary',
      size = 'md',
      className,
      children,
      href,
      ...anchorProps
    } = props

    return (
      <a
        {...anchorProps}
        className={cx(
          'mw-btn',
          `mw-btn--${variant}`,
          `mw-btn--${size}`,
          className,
        )}
        href={href}
      >
        {children}
      </a>
    )
  }

  const {
    variant = 'primary',
    size = 'md',
    className,
    children,
    ...buttonProps
  } = props

  return (
    <button
      {...buttonProps}
      className={cx(
        'mw-btn',
        `mw-btn--${variant}`,
        `mw-btn--${size}`,
        className,
      )}
    >
      {children}
    </button>
  )
}
