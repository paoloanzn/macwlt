import type React from 'react'
import { cx } from '../utils/cx'

export interface CompareRow {
  label: React.ReactNode
  price: React.ReactNode
  win?: boolean
}

export interface PriceCompareProps {
  title: React.ReactNode
  lead?: React.ReactNode
  rows: CompareRow[]
  className?: string
}

export function PriceCompare({
  title,
  lead,
  rows,
  className,
}: PriceCompareProps): React.JSX.Element {
  return (
    <div className={cx('mw-compare', className)}>
      <div className="mw-compare__grid">
        <div>
          <div
            className="mw-display mw-display--md"
            style={{ color: 'var(--mw-heading)' }}
          >
            {title}
          </div>
          {lead && <p className="mw-compare__lead">{lead}</p>}
        </div>
        <div className="mw-compare__rows">
          {rows.map((row, index) => (
            <div
              key={index}
              className={cx(
                'mw-compare__row',
                row.win
                  ? 'mw-compare__row--win'
                  : 'mw-compare__row--muted',
              )}
            >
              <span className="mw-compare__label">{row.label}</span>
              <span className="mw-compare__price">{row.price}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
