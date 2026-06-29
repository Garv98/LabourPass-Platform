import jsPDF from 'jspdf'
import autoTable from 'jspdf-autotable'
import type { Passbook, CertVerify } from './api'
import { PUBLIC_BASE_URL } from './supabase'

export function passbookPdf(pb: Passbook) {
  const doc = new jsPDF()
  const w = pb.worker!
  doc.setFontSize(18).setTextColor('#0f766e').text('LabourPass — Digital Labour Passbook', 14, 18)
  doc.setFontSize(11).setTextColor('#334155')
  doc.text(`Worker: ${w.name}`, 14, 28)
  doc.text(`ID: ${w.public_id}`, 14, 34)
  doc.text(`Location: ${[w.district, w.state].filter(Boolean).join(', ') || '—'}`, 14, 40)
  doc.text(`Skills: ${w.skills.join(', ') || '—'}`, 14, 46)

  const s = pb.summary!
  autoTable(doc, {
    startY: 54,
    head: [['Days Worked', 'Days Absent', 'Total Wages', 'Employers', 'Certificates']],
    body: [[s.days_worked, s.days_absent, '₹' + Number(s.total_wages).toLocaleString('en-IN'), s.employers, s.certificates]],
    theme: 'grid',
    headStyles: { fillColor: [15, 118, 110] },
  })

  autoTable(doc, {
    head: [['Date', 'Amount', 'Mode', 'Employer']],
    body: (pb.wages ?? []).map((g) => [g.payment_date, '₹' + Number(g.amount).toLocaleString('en-IN'), g.mode, g.employer]),
    theme: 'striped',
    headStyles: { fillColor: [15, 118, 110] },
  })

  doc.setFontSize(9).setTextColor('#94a3b8')
  doc.text(`Verify: ${PUBLIC_BASE_URL}/verify/passbook/${w.public_id}`, 14, doc.internal.pageSize.height - 10)
  doc.save(`passbook-${w.public_id}.pdf`)
}

export function certificatePdf(v: CertVerify) {
  const c = v.certificate!
  const doc = new jsPDF()
  doc.setFontSize(20).setTextColor('#0f766e').text('Experience Certificate', 105, 24, { align: 'center' })
  doc.setDrawColor('#0f766e').rect(8, 8, 194, 281)
  doc.setFontSize(12).setTextColor('#334155')
  const lines = [
    `Certificate No: ${c.certificate_no}`,
    `This certifies that ${c.worker_name} (${c.worker_public_id})`,
    `worked as ${c.role} at ${c.worksite || '—'}`,
    `for ${c.employer_name}`,
    `from ${c.start_date} to ${c.end_date} (${c.total_days} days).`,
    `Skills: ${(c.skills ?? []).join(', ') || '—'}`,
    `Conduct: ${c.conduct || '—'}`,
  ]
  lines.forEach((l, i) => doc.text(l, 20, 50 + i * 12))
  if (c.is_revoked) {
    doc.setTextColor('#dc2626').setFontSize(28).text('REVOKED', 105, 160, { align: 'center', angle: 20 })
  }
  doc.setFontSize(9).setTextColor('#94a3b8')
  doc.text(`Verify: ${PUBLIC_BASE_URL}/verify/cert/${c.certificate_no}`, 20, 270)
  doc.save(`${c.certificate_no}.pdf`)
}
