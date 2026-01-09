"use client";

import React from "react";
import { FloatingDock } from "@/components/ui/floating-dock";
import { motion } from "framer-motion";
import {
  IconHome,
  IconBug,
  IconPackage,
  IconBolt,
  IconMap,
  IconChartBar,
  IconUsers,
  IconSword,
  IconHeart,
  IconSparkles,
  IconCloud,
  IconMoodSmile,
  IconTrophy,
  IconTarget,
} from "@tabler/icons-react";

export function FloatingNav() {
  const links = [
    {
      title: "Home",
      icon: (
        <IconHome className="h-full w-full text-neutral-600" />
      ),
      href: "/",
    },
    {
      title: "Creatures",
      icon: (
        <IconBug className="h-full w-full text-neutral-600" />
      ),
      href: "/creatures",
    },
    {
      title: "Items",
      icon: (
        <IconPackage className="h-full w-full text-neutral-600" />
      ),
      href: "/items",
    },
    {
      title: "Moves",
      icon: (
        <IconBolt className="h-full w-full text-neutral-600" />
      ),
      href: "/moves",
    },
    {
      title: "Abilities",
      icon: (
        <IconSparkles className="h-full w-full text-neutral-600" />
      ),
      href: "/abilities",
    },
    {
      title: "Weather",
      icon: (
        <IconCloud className="h-full w-full text-neutral-600" />
      ),
      href: "/weather",
    },
    {
      title: "Natures",
      icon: (
        <IconMoodSmile className="h-full w-full text-neutral-600" />
      ),
      href: "/natures",
    },
    {
      title: "Locations",
      icon: (
        <IconMap className="h-full w-full text-neutral-600" />
      ),
      href: "/locations",
    },
    {
      title: "Challenges",
      icon: (
        <IconTarget className="h-full w-full text-neutral-600" />
      ),
      href: "/challenges",
    },
    {
      title: "Tools",
      icon: (
        <IconChartBar className="h-full w-full text-neutral-600" />
      ),
      href: "/tools",
    },
    {
      title: "Compare",
      icon: (
        <IconUsers className="h-full w-full text-neutral-600" />
      ),
      href: "/compare",
    },
    {
      title: "Team Builder",
      icon: (
        <IconSword className="h-full w-full text-neutral-600" />
      ),
      href: "/team-builder",
    },
    {
      title: "Favorites",
      icon: (
        <IconHeart className="h-full w-full text-neutral-600" />
      ),
      href: "/favorites",
    },
  ];

  return (
    <>
      {/* Desktop navbar with animation */}
      <div className="fixed top-8 left-1/2 transform -translate-x-1/2 z-50 hidden md:block">
        <motion.div 
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{
            duration: 0.6,
            ease: [0.4, 0, 0.2, 1],
          }}
        >
          <FloatingDock items={links} />
        </motion.div>
      </div>
      {/* Mobile navbar with same animation and positioning as desktop */}
      <div className="fixed top-8 left-1/2 transform -translate-x-1/2 z-50 md:hidden">
        <motion.div 
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{
            duration: 0.6,
            ease: [0.4, 0, 0.2, 1],
          }}
        >
          <FloatingDock items={links} />
        </motion.div>
      </div>
    </>
  );
}
