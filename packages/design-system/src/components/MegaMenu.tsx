import type React from 'react'
import { cx } from '../utils/cx'
import { Button } from './Button'
import { ChevronDown, Close, Globe } from './Icons'
import { Wordmark } from './Wordmark'

export interface MegaColumn {
  heading: string
  links: string[]
}

export interface MegaMenuProps {
  navItems?: Array<{ label: string; active?: boolean }>
  feature: React.ReactNode
  bands: React.ReactNode
  columns?: MegaColumn[]
  columnsFooter?: React.ReactNode
  ctaLabel?: string
  onClose?: () => void
  className?: string
}

export function MegaMenu({
  navItems = [],
  feature,
  bands,
  columns = [],
  columnsFooter,
  ctaLabel = 'Get macwlt',
  onClose,
  className,
}: MegaMenuProps): React.JSX.Element {
  return (
    <div className={cx('mw-mega', className)}>
      <div className="mw-mega__bar">
        <div className="mw-mega__bar-left">
          <Wordmark />
          <div className="mw-mega__bar-nav">
            {navItems.map((item) =>
              item.active ? (
                <span key={item.label} className="mw-mega__navitem--active">
                  {item.label}
                  <ChevronDown />
                </span>
              ) : (
                <span key={item.label} className="mw-mega__navitem">
                  {item.label}
                </span>
              ),
            )}
          </div>
        </div>
        <div className="mw-mega__bar-right">
          <span className="mw-mega__lang">
            English
            <Globe />
          </span>
          <Button variant="dark" size="sm">
            {ctaLabel}
          </Button>
          <button
            type="button"
            className="mw-iconbtn mw-iconbtn--soft"
            style={{ width: 48, height: 48 }}
            aria-label="Close"
            onClick={onClose}
          >
            <Close />
          </button>
        </div>
      </div>

      <div className="mw-mega__body">
        <div className="mw-mega__feature">{feature}</div>
        <div className="mw-mega__bands">{bands}</div>
        <div className="mw-mega__col">
          {columns.map((column) => (
            <div key={column.heading}>
              <div className="mw-mega__col-head">{column.heading}</div>
              <div className="mw-mega__links">
                {column.links.map((link) => (
                  <span key={link} className="mw-mega__link">
                    {link}
                  </span>
                ))}
              </div>
            </div>
          ))}
          {columnsFooter}
        </div>
      </div>
    </div>
  )
}
