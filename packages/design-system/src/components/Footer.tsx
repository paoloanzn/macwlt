import type React from 'react'
import { cx } from '../utils/cx'
import { Wordmark } from './Wordmark'

export interface FooterColumn {
  heading: string
  links: Array<{
    label: string
    href: string
    external?: boolean
  }>
}

export interface FooterProps {
  blurb?: React.ReactNode
  columns?: FooterColumn[]
  legal?: React.ReactNode[]
  className?: string
}

export function Footer({
  blurb,
  columns = [],
  legal = [],
  className,
}: FooterProps): React.JSX.Element {
  return (
    <footer className={cx('mw-footer', className)}>
      <div className="mw-container">
        <div className="mw-footer__top">
          <div>
            <Wordmark size={30} />
            {blurb && <p className="mw-footer__blurb">{blurb}</p>}
          </div>
          <div className="mw-footer__cols">
            {columns.map((column) => (
              <div className="mw-footer__col" key={column.heading}>
                <span className="mw-footer__heading">{column.heading}</span>
                {column.links.map((link) => (
                  <a
                    key={`${link.href}-${link.label}`}
                    href={link.href}
                    className={link.external ? 'mw-textlink' : undefined}
                  >
                    {link.label}
                  </a>
                ))}
              </div>
            ))}
          </div>
        </div>
        {legal.length > 0 && (
          <div className="mw-footer__legal">
            {legal.map((node, index) => (
              <span key={index}>{node}</span>
            ))}
          </div>
        )}
      </div>
    </footer>
  )
}
