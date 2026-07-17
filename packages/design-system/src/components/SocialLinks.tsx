import type React from 'react'
import { cx } from '../utils/cx'
import {
  DiscordLogo,
  GitHubLogo,
  LinkedInLogo,
  XLogo,
  YouTubeLogo,
} from './Icons'

export type SocialKind = 'x' | 'github' | 'youtube' | 'discord' | 'linkedin'

export interface SocialItem {
  kind: SocialKind
  href: string
  label?: string
}

const GLYPH: Record<
  SocialKind,
  React.ComponentType<{ size?: number }>
> = {
  x: XLogo,
  github: GitHubLogo,
  youtube: YouTubeLogo,
  discord: DiscordLogo,
  linkedin: LinkedInLogo,
}

export interface SocialLinksProps {
  items: SocialItem[]
  large?: boolean
  className?: string
}

export function SocialLinks({
  items,
  large,
  className,
}: SocialLinksProps): React.JSX.Element {
  return (
    <div className={cx('mw-socials', className)}>
      {items.map((item) => {
        const Glyph = GLYPH[item.kind]

        return (
          <a
            key={`${item.kind}-${item.href}`}
            href={item.href}
            aria-label={item.label ?? item.kind}
            className={cx('mw-social', large && 'mw-social--lg')}
          >
            <Glyph />
          </a>
        )
      })}
    </div>
  )
}
