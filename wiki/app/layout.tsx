import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { FloatingNav } from "@/components/FloatingNav";
import { ClientPageTransition } from "@/components/ClientPageTransition";
import { BackgroundEffects } from "@/components/BackgroundEffects";
import { GlobalSearchWrapper } from "@/components/GlobalSearchWrapper";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Brainrot Catchers Wiki",
  description: "Official wiki for Brainrot Catchers - Complete database of creatures, items, moves, and locations",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${inter.className} bg-slate-50 text-slate-900 min-h-screen flex flex-col relative`}>
        <BackgroundEffects />
        <div className="relative z-20 flex flex-col min-h-screen">
          <FloatingNav />
          <div className="fixed top-24 right-4 md:right-8 z-40 hidden md:block">
            <GlobalSearchWrapper />
          </div>
          <main className="flex-grow container mx-auto px-4 pt-24 pb-24 md:pb-8 md:px-6 md:pt-36 lg:px-8 max-w-7xl">
            <ClientPageTransition>
              {children}
            </ClientPageTransition>
          </main>
          <footer className="bg-transparent mt-12 py-8 text-center text-white text-sm">
            <p>© {new Date().getFullYear()} Brainrot Catchers Wiki. All rights reserved.</p>
          </footer>
        </div>
      </body>
    </html>
  );
}
