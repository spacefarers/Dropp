import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Dropp',
  description: 'Your cross-platform dropzone HQ.',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
