"use client";

import { cn } from "@/lib/utils";
import { cva, type VariantProps } from "class-variance-authority";
import {
  useMotionValue,
  motion,
  useMotionValueEvent,
  useTransform,
  useSpring,
} from "framer-motion";
import Link from "next/link";
import React from "react";

const floatingDockVariants = cva(
  "flex h-full w-full items-end justify-center pb-3",
  {
    variants: {
      variant: {
        default: "",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
);

interface FloatingDockItem {
  title: string;
  icon: React.ReactNode;
  href: string;
  onClick?: () => void;
}

interface FloatingDockProps extends VariantProps<typeof floatingDockVariants> {
  items: FloatingDockItem[];
  desktopClassName?: string;
  mobileClassName?: string;
  className?: string;
}

export const FloatingDock = ({
  items,
  desktopClassName,
  mobileClassName,
  className,
  variant,
}: FloatingDockProps) => {
  return (
    <>
      <FloatingDockDesktop
        items={items}
        className={cn(desktopClassName, className)}
        variant={variant}
      />
      <FloatingDockMobile
        items={items}
        className={cn(mobileClassName, className)}
        variant={variant}
      />
    </>
  );
};

const FloatingDockMobile = ({
  items,
  className,
  variant,
}: {
  items: FloatingDockItem[];
  className?: string;
  variant?: VariantProps<typeof floatingDockVariants>["variant"];
}) => {
  return (
    <div className={cn("fixed bottom-0 left-0 right-0 z-50 md:hidden pb-safe", className)}>
      <div className="mb-4 mx-4 flex h-16 gap-3 rounded-2xl border border-gray-200 bg-white px-3 shadow-lg overflow-x-auto scrollbar-hide">
        {items.map((item) => (
          <MobileIconContainer key={item.title} {...item} />
        ))}
      </div>
    </div>
  );
};

function MobileIconContainer({
  title,
  icon,
  href,
  onClick,
}: {
  title: string;
  icon: React.ReactNode;
  href: string;
  onClick?: () => void;
}) {
  const [isHovered, setIsHovered] = React.useState(false);

  return (
    <Link
      href={href}
      prefetch={true}
      className="relative flex flex-shrink-0 aspect-square h-12 w-12 items-center justify-center rounded-full bg-gray-100 text-gray-600 transition-all duration-300 ease-out hover:bg-gray-200 active:scale-95 active:bg-gray-300 group"
      onClick={onClick}
      onTouchStart={() => setIsHovered(true)}
      onTouchEnd={() => setTimeout(() => setIsHovered(false), 200)}
    >
      {icon}
      <motion.div
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: isHovered ? 1 : 0, y: isHovered ? 0 : 10 }}
        transition={{
          duration: 0.2,
          ease: [0.4, 0, 0.2, 1],
        }}
        className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-md bg-gray-800 px-3 py-1.5 text-xs font-medium text-white pointer-events-none z-50 shadow-lg"
      >
        {title}
      </motion.div>
    </Link>
  );
}

const FloatingDockDesktop = ({
  items,
  className,
  variant,
}: {
  items: FloatingDockItem[];
  className?: string;
  variant?: VariantProps<typeof floatingDockVariants>["variant"];
}) => {
  let mouseX = useMotionValue(Infinity);

  return (
    <motion.div
      onMouseMove={(e) => mouseX.set(e.pageX)}
      onMouseLeave={() => mouseX.set(Infinity)}
      transition={{
        type: "spring",
        stiffness: 100,
        damping: 15,
      }}
      className={cn(
        floatingDockVariants({ variant }),
        "mx-auto hidden md:flex h-16 gap-4 rounded-2xl bg-white px-4 pb-3 shadow-lg border border-gray-200",
        className
      )}
    >
      {items.map((item) => (
        <IconContainer mouseX={mouseX} key={item.title} {...item} />
      ))}
    </motion.div>
  );
};

function IconContainer({
  mouseX,
  title,
  icon,
  href,
  onClick,
}: {
  mouseX: any;
  title: string;
  icon: React.ReactNode;
  href: string;
  onClick?: () => void;
}) {
  let ref = React.useRef<HTMLDivElement>(null);
  const [isHovered, setIsHovered] = React.useState(false);

  let distance = useTransform(mouseX, (val: number) => {
    let bounds = ref.current?.getBoundingClientRect() ?? { x: 0, width: 0 };

    return val - bounds.x - bounds.width / 2;
  });

  let widthTransform = useTransform(distance, [-150, 0, 150], [40, 80, 40]);
  let heightTransform = useTransform(distance, [-150, 0, 150], [40, 80, 40]);

  let widthTransformIcon = useTransform(distance, [-150, 0, 150], [20, 40, 20]);
  let heightTransformIcon = useTransform(
    distance,
    [-150, 0, 150],
    [20, 40, 20]
  );

  // Use spring animations for smoother transitions
  let width = useSpring(widthTransform, {
    stiffness: 120,
    damping: 20,
    mass: 0.5,
  });
  let height = useSpring(heightTransform, {
    stiffness: 120,
    damping: 20,
    mass: 0.5,
  });
  let widthIcon = useSpring(widthTransformIcon, {
    stiffness: 120,
    damping: 20,
    mass: 0.5,
  });
  let heightIcon = useSpring(heightTransformIcon, {
    stiffness: 120,
    damping: 20,
    mass: 0.5,
  });

  const handleClick = (e: React.MouseEvent) => {
    if (onClick) {
      onClick();
    }
    // Let Link handle navigation - it's more reliable for Next.js transitions
  };

  return (
    <Link
      href={href}
      prefetch={true}
      onClick={handleClick}
      className="block group"
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      <motion.div
        ref={ref}
        style={{ 
          width, 
          height,
        }}
        className="aspect-square rounded-full bg-gray-100 flex items-center justify-center relative transition-colors duration-300 hover:bg-gray-200 cursor-pointer"
      >
        <motion.div
          style={{ width: widthIcon, height: heightIcon }}
          className="flex items-center justify-center pointer-events-none"
        >
          {icon}
        </motion.div>
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: isHovered ? 1 : 0, y: isHovered ? 0 : 10 }}
          transition={{
            duration: 0.2,
            ease: [0.4, 0, 0.2, 1],
          }}
          className="absolute top-full mt-2 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-md bg-gray-800 px-3 py-1.5 text-xs font-medium text-white pointer-events-none z-50 shadow-lg"
        >
          {title}
        </motion.div>
      </motion.div>
    </Link>
  );
}
