import { Header } from '@/components/Header'
import { HeroSection } from '@/components/HeroSection'
import { FeaturesSection } from '@/components/FeaturesSection'
import { InstallationSection } from '@/components/InstallationSection'
import { CommunitySection } from '@/components/CommunitySection'
import { Footer } from '@/components/Footer'

export default function Home() {
  return (
    <main className="min-h-screen">
      <Header />
      <HeroSection />
      <FeaturesSection />
      <InstallationSection />
      <CommunitySection />
      <Footer />
    </main>
  )
}
