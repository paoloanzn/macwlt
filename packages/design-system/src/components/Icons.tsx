import type React from 'react'

type IconProps = React.SVGProps<SVGSVGElement> & { size?: number }

function iconProps({
  size = 24,
  ...props
}: IconProps): React.SVGProps<SVGSVGElement> {
  return {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    ...props,
  }
}

export function ChevronDown({
  size = 12,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })} viewBox="0 0 12 12">
      <path
        d="M2.5 4.5L6 8l3.5-3.5"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export function ChevronRight({
  size = 16,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })} viewBox="0 0 18 18">
      <path
        d="M6.5 4L11 9l-4.5 5"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export function Close({
  size = 16,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })} viewBox="0 0 16 16">
      <path
        d="M3 3l10 10M13 3L3 13"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </svg>
  )
}

export function Globe({
  size = 16,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })} viewBox="0 0 16 16">
      <circle
        cx="8"
        cy="8"
        r="6.4"
        stroke="currentColor"
        strokeWidth="1.3"
      />
      <path
        d="M1.6 8h12.8M8 1.6c1.8 1.7 2.8 4 2.8 6.4S9.8 12.7 8 14.4C6.2 12.7 5.2 10.4 5.2 8S6.2 3.3 8 1.6Z"
        stroke="currentColor"
        strokeWidth="1.3"
      />
    </svg>
  )
}

export function Check({
  size = 24,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })}>
      <path
        d="M5 12.5l4.5 4.5L19 7"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export function Lock({
  size = 24,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })}>
      <rect
        x="4.5"
        y="10.5"
        width="15"
        height="10"
        rx="2.4"
        stroke="currentColor"
        strokeWidth="1.8"
      />
      <path
        d="M8 10.5V8a4 4 0 0 1 8 0v2.5"
        stroke="currentColor"
        strokeWidth="1.8"
      />
      <circle cx="12" cy="15.5" r="1.6" fill="currentColor" />
    </svg>
  )
}

export function Chip({
  size = 24,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })}>
      <rect
        x="5"
        y="5"
        width="14"
        height="14"
        rx="3"
        stroke="currentColor"
        strokeWidth="1.6"
      />
      <path
        d="M9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
      />
    </svg>
  )
}

export function Fingerprint({
  size = 24,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg
      {...iconProps({ size, ...props })}
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
    >
      <path d="M12 3.5a7 7 0 0 0-7 7v2" />
      <path d="M12 3.5a7 7 0 0 1 7 7v3.5a6 6 0 0 1-.6 2.6" />
      <path d="M8.5 11a3.5 3.5 0 0 1 7 0v3.5c0 1 .1 2-.3 3" />
      <path d="M12 11v4.5c0 1.4-.3 2.6-1 3.8" />
      <path d="M5 16.5c.5 1 .7 2 .7 3.2" />
    </svg>
  )
}

export function Shield({
  size = 24,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg
      {...iconProps({ size, ...props })}
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M12 3l7 3v5c0 5-3 8.5-7 10-4-1.5-7-5-7-10V6l7-3Z" />
      <path d="M12 8v4l3 2" />
    </svg>
  )
}

export function Code({
  size = 24,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg
      {...iconProps({ size, ...props })}
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M9 8l-4 4 4 4M15 8l4 4-4 4" />
    </svg>
  )
}

export function XLogo({
  size = 15,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })} fill="currentColor">
      <path d="M18.9 2H22l-7.5 8.6L23 22h-6.8l-5.3-6.9L4.8 22H1.7l8-9.2L1 2h6.9l4.8 6.3L18.9 2Zm-1.2 18h1.9L7.1 4H5.1l12.6 16Z" />
    </svg>
  )
}

export function GitHubLogo({
  size = 17,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })} fill="currentColor">
      <path d="M12 2C6.5 2 2 6.6 2 12.3c0 4.5 2.9 8.4 6.8 9.7.5.1.7-.2.7-.5v-1.7c-2.8.6-3.4-1.4-3.4-1.4-.4-1.2-1.1-1.5-1.1-1.5-.9-.6.1-.6.1-.6 1 .1 1.5 1 1.5 1 .9 1.6 2.4 1.1 3 .8.1-.7.3-1.1.6-1.4-2.2-.3-4.6-1.1-4.6-5.1 0-1.1.4-2 1-2.7-.1-.3-.4-1.3.1-2.7 0 0 .8-.3 2.7 1a9 9 0 0 1 5 0c1.9-1.3 2.7-1 2.7-1 .5 1.4.2 2.4.1 2.7.6.7 1 1.6 1 2.7 0 4-2.4 4.8-4.7 5.1.4.3.7.9.7 1.9v2.8c0 .3.2.6.7.5 3.9-1.3 6.8-5.2 6.8-9.7C22 6.6 17.5 2 12 2Z" />
    </svg>
  )
}

export function YouTubeLogo({
  size = 17,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })} fill="currentColor">
      <path d="M23 7.5a3 3 0 0 0-2.1-2.1C19 4.8 12 4.8 12 4.8s-7 0-8.9.6A3 3 0 0 0 1 7.5C.4 9.4.4 12 .4 12s0 2.6.6 4.5a3 3 0 0 0 2.1 2.1c1.9.6 8.9.6 8.9.6s7 0 8.9-.6a3 3 0 0 0 2.1-2.1c.6-1.9.6-4.5.6-4.5s0-2.6-.6-4.5ZM9.7 15.4V8.6l5.8 3.4-5.8 3.4Z" />
    </svg>
  )
}

export function DiscordLogo({
  size = 17,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })} fill="currentColor">
      <path d="M20 4.4A19 19 0 0 0 15.3 3l-.3.5a14 14 0 0 1 4.1 1.3A13 13 0 0 0 3.9 4.8 14 14 0 0 1 8 3.5L7.7 3A19 19 0 0 0 3 4.4C.8 8.3.2 12.1.5 15.9a19 19 0 0 0 5.8 2.9l.5-.9a12 12 0 0 1-1.8-.9l.4-.3a13 13 0 0 0 11.2 0l.4.3c-.6.3-1.2.6-1.8.9l.5.9a19 19 0 0 0 5.8-2.9c.4-4.4-.6-8.2-2.5-11.5ZM8.3 13.7c-.9 0-1.7-.9-1.7-1.9s.8-1.9 1.7-1.9 1.7.9 1.7 1.9-.7 1.9-1.7 1.9Zm7.4 0c-.9 0-1.7-.9-1.7-1.9s.8-1.9 1.7-1.9 1.7.9 1.7 1.9-.7 1.9-1.7 1.9Z" />
    </svg>
  )
}

export function LinkedInLogo({
  size = 17,
  ...props
}: IconProps): React.JSX.Element {
  return (
    <svg {...iconProps({ size, ...props })} fill="currentColor">
      <path d="M20.3 3H3.7C3.3 3 3 3.3 3 3.7v16.6c0 .4.3.7.7.7h16.6c.4 0 .7-.3.7-.7V3.7c0-.4-.3-.7-.7-.7ZM8.3 18.3H5.4V9.7h2.9v8.6ZM6.9 8.4a1.7 1.7 0 1 1 0-3.4 1.7 1.7 0 0 1 0 3.4Zm11.4 9.9h-2.9v-4.2c0-1 0-2.3-1.4-2.3s-1.6 1.1-1.6 2.2v4.3H9.5V9.7h2.8v1.2h.1c.4-.7 1.3-1.5 2.7-1.5 2.9 0 3.4 1.9 3.4 4.4v4.5Z" />
    </svg>
  )
}
