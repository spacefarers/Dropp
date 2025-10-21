import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  experimental: { optimizePackageImports: ['firebase'] },
};

export default nextConfig;
