import type React from 'react'
import { cx } from '../utils/cx'
import { Button } from './Button'
import { ChevronDown, ChevronRight, Close, Globe } from './Icons'
import { Wordmark } from './Wordmark'

export interface MobileMenuProps {
  primary: string[]
  secondary?: string[]
  ctaLabel?: string
  language?: string
  socials?: React.ReactNode
  onClose?: () => void
  className?: string
}

export function MobileMenu({
  primary,
  secondary = [],
  ctaLabel = 'Get macwlt',
  language = 'English',
  socials,
  onClose,
  className,
}: MobileMenuProps): React.JSX.Element {
  return (
    <div className={cx('mw-mobile', className)}>
      <div className="mw-mobile__head">
        <Wordmark size={24} />
        <button
          type="button"
          className="mw-iconbtn"
          style={{ width: 46, height: 46 }}
          aria-label="Close"
          onClick={onClose}
        >
          <Close />
        </button>
      </div>

      <Button
        variant="accent"
        size="md"
        style={{ width: '100%', marginBottom: 8 }}
      >
        {ctaLabel}
      </Button>

      <div className="mw-mobile__rows">
        {primary.map((row) => (
          <div className="mw-mobile__row" key={row}>
            <span className="mw-mobile__row-title">{row}</span>
            <ChevronDown
              size={18}
              style={{ color: 'var(--mw-heading)' }}
            />
          </div>
        ))}
      </div>

      {secondary.length > 0 && (
        <div className="mw-mobile__rows" style={{ marginTop: 12 }}>
          {secondary.map((row) => (
            <div className="mw-mobile__row mw-mobile__row--sub" key={row}>
              <span className="mw-mobile__row-title">{row}</span>
              <ChevronRight
                size={16}
                style={{ color: 'var(--mw-muted-dim)' }}
              />
            </div>
          ))}
        </div>
      )}

      <div className="mw-mobile__footer">
        <Globe size={18} />
        <span>{language}</span>
      </div>

      {socials}
    </div>
  )
}
