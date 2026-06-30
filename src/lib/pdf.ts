import jsPDF from 'jspdf'
import autoTable from 'jspdf-autotable'
import QRCode from 'qrcode'
import type { Passbook, CertVerify } from './api'
import { PUBLIC_BASE_URL } from './supabase'

// Government work-passbook styling for the exported PDFs — header band, civic
// seal, boxed registration cells, ruled ledgers, rubber stamp, scannable QR.

const TEAL: [number, number, number] = [15, 118, 110]
const TEAL_DEEP: [number, number, number] = [11, 79, 74]
const INK: [number, number, number] = [21, 48, 43]
const INK_SOFT: [number, number, number] = [74, 91, 82]
const STAMP: [number, number, number] = [179, 54, 31]
const CREAM: [number, number, number] = [253, 250, 233]
const PAID: [number, number, number] = [31, 122, 61]

const inr = (n: number | string | undefined) => 'Rs.' + Number(n ?? 0).toLocaleString('en-IN')

function seal(doc: jsPDF, cx: number, cy: number, r: number, color: [number, number, number]) {
  doc.setDrawColor(...color).setLineWidth(0.4)
  doc.circle(cx, cy, r)
  doc.setFillColor(...color).circle(cx, cy, 1, 'F')
  for (let i = 0; i < 24; i++) {
    const a = (i * 15 * Math.PI) / 180
    doc.line(cx + 1.6 * Math.cos(a), cy + 1.6 * Math.sin(a), cx + r * 0.92 * Math.cos(a), cy + r * 0.92 * Math.sin(a))
  }
}

function stamp(doc: jsPDF, cx: number, cy: number, label: string, color: [number, number, number]) {
  doc.setDrawColor(...color).setLineWidth(0.6)
  doc.roundedRect(cx - 17, cy - 7.5, 34, 15, 2, 2)
  doc.setLineWidth(0.3).roundedRect(cx - 15.5, cy - 6, 31, 12, 1.5, 1.5)
  doc.setTextColor(...color).setFont('helvetica', 'bold').setFontSize(12)
  doc.text(label, cx, cy + 1.5, { align: 'center' })
}

function serial(doc: jsPDF, x: number, y: number, id: string) {
  doc.setFont('courier', 'bold').setFontSize(11).setTextColor(...INK).setDrawColor(...INK).setLineWidth(0.3)
  const cw = 5.6, ch = 7.4
  let cx = x
  for (const ch2 of id.split('')) {
    doc.rect(cx, y, cw, ch)
    doc.text(ch2, cx + cw / 2, y + ch - 2.2, { align: 'center' })
    cx += cw + 1
  }
}

export async function passbookPdf(pb: Passbook) {
  const w = pb.worker!
  const s = pb.summary!
  const doc = new jsPDF('p', 'mm', 'a4')
  const W = 210, H = 297, M = 12
  const link = `${PUBLIC_BASE_URL}/verify/passbook/${w.public_id}`

  doc.setDrawColor(...INK).setLineWidth(0.8).rect(M, M, W - 2 * M, H - 2 * M)

  // header band
  doc.setFillColor(...TEAL_DEEP).rect(M, M, W - 2 * M, 26, 'F')
  seal(doc, M + 13, M + 13, 8, CREAM)
  doc.setTextColor(...CREAM).setFont('helvetica', 'bold').setFontSize(17).text('LabourPass', M + 26, M + 12)
  doc.setFont('helvetica', 'normal').setFontSize(9.5).text('WORKER PASSBOOK  ·  Verified Work Record', M + 26, M + 19)
  stamp(doc, W - M - 26, M + 13, 'VERIFIED', [255, 217, 207])

  // identity
  const idY = M + 36
  doc.setDrawColor(...INK).setLineWidth(0.4).rect(M + 6, idY, 22, 28)
  doc.setTextColor(...INK_SOFT).setFontSize(7).setFont('helvetica', 'normal').text('PHOTO', M + 17, idY + 15, { align: 'center' })

  doc.setTextColor(...INK).setFont('helvetica', 'bold').setFontSize(19).text(w.name, M + 34, idY + 8)
  doc.setFont('helvetica', 'normal').setFontSize(8.5).setTextColor(...INK_SOFT).text('REGISTRATION NO.', M + 34, idY + 14)
  serial(doc, M + 34, idY + 16, w.public_id)
  doc.setTextColor(...INK).setFontSize(10)
  doc.text([w.district, w.state].filter(Boolean).join(', ') || '-', M + 34, idY + 30)
  doc.text('Skills: ' + (w.skills.join(', ') || '-'), M + 34, idY + 36)

  const qr = await QRCode.toDataURL(link, { margin: 0, width: 160 })
  doc.addImage(qr, 'PNG', W - M - 30, idY + 2, 24, 24)
  doc.setFontSize(7).setTextColor(...INK_SOFT).text('Scan to verify', W - M - 18, idY + 29, { align: 'center' })

  // work summary
  let y = idY + 46
  doc.setFont('helvetica', 'bold').setFontSize(11).setTextColor(...TEAL_DEEP).text('WORK SUMMARY', M + 6, y)
  autoTable(doc, {
    startY: y + 2,
    margin: { left: M + 6, right: M + 6 },
    head: [['Days Worked', 'Days Absent', 'Total Wages', 'Employers', 'Certificates']],
    body: [[s.days_worked, s.days_absent, inr(s.total_wages), s.employers, s.certificates]],
    theme: 'grid',
    headStyles: { fillColor: TEAL, textColor: CREAM, fontStyle: 'bold', halign: 'center' },
    styles: { halign: 'center', fontSize: 10, lineColor: [202, 189, 150] },
  })

  // wage ledger (lastAutoTable is injected by the autotable plugin)
  y = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 8
  doc.setFont('helvetica', 'bold').setFontSize(11).setTextColor(...TEAL_DEEP).text('WAGE LEDGER', M + 6, y)
  autoTable(doc, {
    startY: y + 2,
    margin: { left: M + 6, right: M + 6 },
    head: [['Date', 'Amount', 'Mode', 'Employer', 'Status']],
    body: (pb.wages ?? []).map((g) => [g.payment_date, inr(g.amount), g.mode, g.employer, 'PAID']),
    theme: 'striped',
    headStyles: { fillColor: TEAL, textColor: CREAM },
    styles: { fontSize: 9, lineColor: [202, 189, 150] },
    didParseCell: (data) => {
      if (data.section === 'body' && data.column.index === 4) {
        data.cell.styles.textColor = PAID
        data.cell.styles.fontStyle = 'bold'
      }
    },
  })

  // footer band
  doc.setFillColor(...TEAL_DEEP).rect(M, H - M - 14, W - 2 * M, 14, 'F')
  doc.setTextColor(...CREAM).setFont('helvetica', 'normal').setFontSize(8)
  doc.text('Tamper-evident · hash-chained · Share with banks, welfare boards & new employers', M + 6, H - M - 8)
  doc.text(link, M + 6, H - M - 3.5)

  doc.save(`passbook-${w.public_id}.pdf`)
}

export async function certificatePdf(v: CertVerify) {
  const c = v.certificate!
  const doc = new jsPDF('p', 'mm', 'a4')
  const W = 210, H = 297, M = 14
  const link = `${PUBLIC_BASE_URL}/verify/cert/${c.certificate_no}`

  // ornamental double border
  doc.setDrawColor(...TEAL).setLineWidth(1.2).rect(M, M, W - 2 * M, H - 2 * M)
  doc.setLineWidth(0.4).rect(M + 3, M + 3, W - 2 * M - 6, H - 2 * M - 6)

  // header band
  doc.setFillColor(...TEAL_DEEP).rect(M + 3, M + 3, W - 2 * M - 6, 24, 'F')
  seal(doc, M + 17, M + 15, 8, CREAM)
  doc.setTextColor(...CREAM).setFont('helvetica', 'bold').setFontSize(19).text('Experience Certificate', W / 2, M + 14, { align: 'center' })
  doc.setFont('helvetica', 'normal').setFontSize(9).text('LabourPass · Verified Work Record', W / 2, M + 21, { align: 'center' })
  stamp(doc, W - M - 24, M + 15, v.valid ? 'VALID' : 'REVOKED', v.valid ? [255, 217, 207] : STAMP)

  // body (centred)
  const y = 64
  doc.setTextColor(...INK_SOFT).setFont('helvetica', 'normal').setFontSize(11).text('This is to certify that', W / 2, y, { align: 'center' })
  doc.setTextColor(...INK).setFont('helvetica', 'bold').setFontSize(24).text(c.worker_name, W / 2, y + 13, { align: 'center' })
  doc.setFont('helvetica', 'normal').setFontSize(10).setTextColor(...INK_SOFT).text(`Registration No. ${c.worker_public_id}`, W / 2, y + 20, { align: 'center' })

  doc.setTextColor(...INK).setFontSize(12)
  doc.text(`worked as ${c.role} for ${c.employer_name}`, W / 2, y + 33, { align: 'center' })
  doc.text(`from ${c.start_date} to ${c.end_date}  (${c.total_days} days)`, W / 2, y + 41, { align: 'center' })
  if (c.worksite) doc.text(`at ${c.worksite}`, W / 2, y + 49, { align: 'center' })

  doc.setFont('helvetica', 'bold').setFontSize(10).setTextColor(...TEAL_DEEP).text('SKILLS DEMONSTRATED', W / 2, y + 64, { align: 'center' })
  doc.setFont('helvetica', 'normal').setFontSize(11).setTextColor(...INK).text((c.skills ?? []).join('   ·   ') || '-', W / 2, y + 71, { align: 'center' })

  if (c.conduct) {
    doc.setTextColor(...INK_SOFT).setFont('helvetica', 'italic').setFontSize(10)
    doc.text(`"${c.conduct}"`, W / 2, y + 84, { align: 'center', maxWidth: W - 2 * M - 30 })
  }

  // QR (left) + signature (right)
  const qr = await QRCode.toDataURL(link, { margin: 0, width: 160 })
  doc.addImage(qr, 'PNG', M + 12, H - M - 52, 26, 26)
  doc.setFont('helvetica', 'normal').setFontSize(8).setTextColor(...INK_SOFT)
  doc.text('Scan to verify authenticity', M + 12, H - M - 22)
  doc.text('Cert No: ' + c.certificate_no, M + 12, H - M - 17)

  doc.setDrawColor(...INK).setLineWidth(0.3).line(W - M - 64, H - M - 28, W - M - 16, H - M - 28)
  doc.setFontSize(9).setTextColor(...INK_SOFT)
  doc.text('Issued by ' + c.employer_name, W - M - 40, H - M - 23, { align: 'center' })
  doc.text(new Date(c.issued_at).toLocaleDateString('en-IN'), W - M - 40, H - M - 18, { align: 'center' })

  if (c.is_revoked) {
    doc.setTextColor(...STAMP).setFont('helvetica', 'bold').setFontSize(50).text('REVOKED', W / 2, H / 2 + 10, { align: 'center', angle: 18 })
  }

  doc.save(`${c.certificate_no}.pdf`)
}
