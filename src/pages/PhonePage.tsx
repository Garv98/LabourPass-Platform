import { Link } from 'react-router-dom'
import { PhoneSim } from '../components/PhoneSim'
import { Emblem } from '../components/Emblem'

export default function PhonePage() {
  return (
    <div className="lp-paper min-h-full py-8">
      <div className="mx-auto max-w-2xl px-4">
        <Link to="/" className="text-base font-semibold text-band hover:underline">← घर · Home</Link>
        <div className="mt-3 flex items-start gap-3">
          <span className="text-band"><Emblem size={40} /></span>
          <div>
            <h1 className="text-2xl font-bold text-ink">मज़दूर का फ़ोन · Worker's phone</h1>
            <p className="mt-1 max-w-prose text-base text-ink-soft">
              मज़दूर को स्मार्टफ़ोन या ऐप की ज़रूरत नहीं — सब कुछ साधारण SMS से चलता है। यह पैनल असली GSM फ़ोन जैसा है।
              <span className="mt-1 block">
                No smartphone or app needed. Type a reply — PROFILE, WAGES, PASSBOOK, 1/2, DISPUTE — to act as the worker.
                In production the same parser runs behind MSG91/Exotel.
              </span>
            </p>
          </div>
        </div>
        <div className="mt-6 flex justify-center">
          <div className="overflow-hidden border-4 border-ink">
            <PhoneSim />
          </div>
        </div>
      </div>
    </div>
  )
}
