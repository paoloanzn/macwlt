import type React from 'react'
import { cx } from '../utils/cx'
import { Button } from './Button'
import { Wordmark } from './Wordmark'

export interface NavLink {
  label: string
  href: string
}

export interface NavbarProps {
  links?: NavLink[]
  ctaLabel?: string
  ctaHref?: string
  onMenu?: () => void
  hideMenuButton?: boolean
  className?: string
}

export function Navbar({
  links = [],
  ctaLabel = 'Get macwlt',
  ctaHref = '#get',
  onMenu,
  hideMenuButton,
  className,
}: NavbarProps): React.JSX.Element {
  return (
    <header className={cx('mw-navbar', className)}>
      <a href="#top" aria-label="macwlt home">
        <Wordmark />
      </a>
      <nav className="mw-navbar__nav">
        {links.length > 0 && (
          <div className="mw-navbar__links">
            {links.map((link) => (
              <a key={link.href} href={link.href}>
                {link.label}
              </a>
            ))}
          </div>
        )}
        <div className="mw-navbar__actions">
          <Button href={ctaHref} variant="dark" size="sm">
            {ctaLabel}
          </Button>
          {!hideMenuButton && (
            <button
              type="button"
              className="mw-iconbtn"
              aria-label="Menu"
              onClick={onMenu}
            >
              <span className="mw-iconbtn__bar" />
              <span className="mw-iconbtn__bar" />
            </button>
          )}
        </div>
      </nav>
    </header>
  )
}
