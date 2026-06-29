import { useEffect, useState } from 'react'
import QRCode from 'qrcode'

export function QR({ value, size = 128 }: { value: string; size?: number }) {
  const [url, setUrl] = useState('')
  useEffect(() => {
    QRCode.toDataURL(value, { width: size, margin: 1 }).then(setUrl).catch(() => setUrl(''))
  }, [value, size])
  if (!url) return <div style={{ width: size, height: size }} className="animate-pulse rounded bg-slate-100" />
  return <img src={url} width={size} height={size} alt="QR code" className="rounded" />
}
