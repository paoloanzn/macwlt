import type React from 'react'
import { cx } from '../utils/cx'

export interface Step {
  num: string
  title: React.ReactNode
  body: React.ReactNode
}

export interface StepsProps {
  steps: Step[]
  className?: string
}

export function Steps({
  steps,
  className,
}: StepsProps): React.JSX.Element {
  return (
    <div className={cx('mw-steps', className)}>
      {steps.map((step) => (
        <div className="mw-step" key={step.num}>
          <div className="mw-step__num">{step.num}</div>
          <h3 className="mw-step__title">{step.title}</h3>
          <p className="mw-step__body">{step.body}</p>
        </div>
      ))}
    </div>
  )
}
