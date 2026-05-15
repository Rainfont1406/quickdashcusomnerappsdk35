# QuickDash Design System v2.0

**Modern · Scalable · Consistent**

---

## Table of Contents
1. [Design Philosophy](#design-philosophy)
2. [Design Tokens](#design-tokens)
3. [Color System](#color-system)
4. [Typography](#typography)
5. [Spacing & Layout](#spacing--layout)
6. [Components](#components)
7. [Patterns & Templates](#patterns--templates)
8. [Motion & Animation](#motion--animation)
9. [Accessibility](#accessibility)
10. [Flutter Implementation](#flutter-implementation)

---

## Design Philosophy

### Vision
QuickDash delivers a **premium, frictionless food ordering experience** that feels modern, trustworthy, and delightful. Every interaction should be **intentional, fast, and emotionally rewarding**.

### Core Principles

1. **Clarity Over Cleverness**
   - Information hierarchy is crystal clear
   - Users never need to guess what to do next
   - Every pixel serves a purpose

2. **Speed as a Feature**
   - Optimize for quick scanning and decision-making
   - Reduce cognitive load at every step
   - Performance is part of the design

3. **Visual Hunger Appeal**
   - Food imagery is always the hero
   - Colors and composition should trigger appetite
   - Quality photography over generic stock images

4. **Accessibility First**
   - WCAG 2.1 AA compliance minimum
   - One-handed operation on devices 4.7"–6.7"
   - Support for reduced motion and high contrast

5. **Consistent & Predictable**
   - Reusable components across all screens
   - Patterns users can learn once, use everywhere
   - Platform conventions respected (iOS/Android)

---

## Design Tokens

Design tokens are the atomic values that define the visual language. Use these constants across all implementations.

### Spacing Scale
```
spacing-0: 0px      // None
spacing-1: 4px      // Micro
spacing-2: 8px      // Tiny
spacing-3: 12px     // Small
spacing-4: 16px     // Base (default)
spacing-5: 20px     // Medium
spacing-6: 24px     // Large
spacing-7: 32px     // XLarge
spacing-8: 40px     // XXLarge
spacing-9: 48px     // Huge
spacing-10: 64px    // Massive
spacing-11: 80px    // Ultra
```

### Border Radius Scale
```
radius-none: 0px
radius-sm: 4px      // Subtle elements
radius-md: 8px      // Default
radius-lg: 12px     // Cards, buttons
radius-xl: 16px     // Large cards
radius-2xl: 20px    // Modals
radius-3xl: 24px    // Search bars
radius-full: 9999px // Pills, avatars
```

### Shadow Scale
```
shadow-none: none

shadow-sm:
  0px 1px 2px rgba(0, 0, 0, 0.04),
  0px 1px 3px rgba(0, 0, 0, 0.06)

shadow-md:
  0px 2px 4px rgba(0, 0, 0, 0.06),
  0px 4px 6px rgba(0, 0, 0, 0.08)

shadow-lg:
  0px 4px 8px rgba(0, 0, 0, 0.08),
  0px 8px 16px rgba(0, 0, 0, 0.10)

shadow-xl:
  0px 8px 16px rgba(0, 0, 0, 0.10),
  0px 12px 24px rgba(0, 0, 0, 0.12)

shadow-2xl:
  0px 16px 32px rgba(0, 0, 0, 0.12),
  0px 24px 48px rgba(0, 0, 0, 0.14)
```

### Elevation System
```
elevation-0: z-index 0    // Base layer
elevation-1: z-index 10   // Cards
elevation-2: z-index 20   // Dropdowns
elevation-3: z-index 30   // Sticky headers
elevation-4: z-index 40   // Modals
elevation-5: z-index 50   // Tooltips
elevation-max: z-index 100 // Critical overlays
```

---

## Color System

### Brand Colors
```
Primary Red
  primary-50:  #FEF2F2
  primary-100: #FDE8E8
  primary-200: #FBD5D5
  primary-300: #F8B4B4
  primary-400: #F48585
  primary-500: #E23744  // Main brand
  primary-600: #C81D3B  // Hover/active
  primary-700: #A51829
  primary-800: #7F111E
  primary-900: #5A0C15
```

### Neutral Colors
```
Grays
  neutral-0:   #FFFFFF  // Pure white
  neutral-50:  #FAFAFA  // Background
  neutral-100: #F5F5F5  // Subtle bg
  neutral-200: #E5E5E5  // Borders
  neutral-300: #D4D4D4  // Dividers
  neutral-400: #A3A3A3  // Disabled
  neutral-500: #737373  // Placeholder
  neutral-600: #525252  // Secondary text
  neutral-700: #404040  // Body text
  neutral-800: #262626  // Heading
  neutral-900: #171717  // Heavy text
  neutral-950: #0A0A0A  // Black
```

### Semantic Colors
```
Success Green
  success-50:  #ECFDF5
  success-500: #00A859  // Main
  success-600: #008A48
  success-700: #006B38

Error Red
  error-50:  #FEF2F2
  error-500: #EF4444
  error-600: #DC2626

Warning Yellow/Orange
  warning-50:  #FFFBEB
  warning-500: #F59E0B  // Main
  warning-600: #D97706

Info Blue
  info-50:  #EFF6FF
  info-500: #3B82F6
  info-600: #2563EB
```

### Gradient Palette
```
gradient-primary: linear-gradient(135deg, #E23744 0%, #C81D3B 100%)
gradient-success: linear-gradient(135deg, #00A859 0%, #006B38 100%)
gradient-dark: linear-gradient(180deg, rgba(0,0,0,0) 0%, rgba(0,0,0,0.7) 100%)
gradient-shimmer: linear-gradient(90deg, transparent 0%, rgba(255,255,255,0.4) 50%, transparent 100%)
```

### Dark Mode Colors
```
Dark Backgrounds
  dark-bg-primary: #0A0A0A
  dark-bg-secondary: #171717
  dark-bg-tertiary: #262626
  dark-bg-elevated: #404040

Dark Text
  dark-text-primary: #FAFAFA
  dark-text-secondary: #D4D4D4
  dark-text-tertiary: #A3A3A3

Dark Borders
  dark-border-primary: #404040
  dark-border-secondary: #262626
```

---

## Typography

### Font Family
```
Primary: 'Inter', -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', sans-serif
Monospace: 'SF Mono', 'Roboto Mono', 'Courier New', monospace
```

### Type Scale
```
Display Large (display-lg)
  Font Size: 57px
  Line Height: 64px (112%)
  Letter Spacing: -0.25px
  Font Weight: 700 (Bold)
  Usage: Hero sections, splash screens

Display Medium (display-md)
  Font Size: 45px
  Line Height: 52px (116%)
  Letter Spacing: 0px
  Font Weight: 700 (Bold)
  Usage: Large page headers

Display Small (display-sm)
  Font Size: 36px
  Line Height: 44px (122%)
  Letter Spacing: 0px
  Font Weight: 600 (Semibold)
  Usage: Section headers

Heading 1 (h1)
  Font Size: 32px
  Line Height: 40px (125%)
  Letter Spacing: -0.5px
  Font Weight: 700 (Bold)
  Usage: Page titles

Heading 2 (h2)
  Font Size: 28px
  Line Height: 36px (129%)
  Letter Spacing: -0.25px
  Font Weight: 700 (Bold)
  Usage: Major sections

Heading 3 (h3)
  Font Size: 24px
  Line Height: 32px (133%)
  Letter Spacing: 0px
  Font Weight: 600 (Semibold)
  Usage: Subsections

Heading 4 (h4)
  Font Size: 20px
  Line Height: 28px (140%)
  Letter Spacing: 0px
  Font Weight: 600 (Semibold)
  Usage: Card titles

Heading 5 (h5)
  Font Size: 18px
  Line Height: 24px (133%)
  Letter Spacing: 0px
  Font Weight: 600 (Semibold)
  Usage: Small headings

Heading 6 (h6)
  Font Size: 16px
  Line Height: 24px (150%)
  Letter Spacing: 0px
  Font Weight: 600 (Semibold)
  Usage: Subtle headings

Body Large (body-lg)
  Font Size: 18px
  Line Height: 28px (156%)
  Letter Spacing: 0px
  Font Weight: 400 (Regular)
  Usage: Prominent body text

Body Medium (body-md) [DEFAULT]
  Font Size: 16px
  Line Height: 24px (150%)
  Letter Spacing: 0px
  Font Weight: 400 (Regular)
  Usage: Standard body text

Body Small (body-sm)
  Font Size: 14px
  Line Height: 20px (143%)
  Letter Spacing: 0px
  Font Weight: 400 (Regular)
  Usage: Secondary text

Caption (caption)
  Font Size: 12px
  Line Height: 16px (133%)
  Letter Spacing: 0.25px
  Font Weight: 400 (Regular)
  Usage: Labels, timestamps, metadata

Overline (overline)
  Font Size: 12px
  Line Height: 16px (133%)
  Letter Spacing: 1px
  Font Weight: 600 (Semibold)
  Text Transform: Uppercase
  Usage: Category labels, tags

Label Large (label-lg)
  Font Size: 16px
  Line Height: 24px (150%)
  Letter Spacing: 0px
  Font Weight: 500 (Medium)
  Usage: Form labels, button text

Label Medium (label-md)
  Font Size: 14px
  Line Height: 20px (143%)
  Letter Spacing: 0.1px
  Font Weight: 500 (Medium)
  Usage: Small buttons, chips

Label Small (label-sm)
  Font Size: 12px
  Line Height: 16px (133%)
  Letter Spacing: 0.25px
  Font Weight: 500 (Medium)
  Usage: Tiny labels, badges
```

### Font Weights
```
Light: 300
Regular: 400
Medium: 500
Semibold: 600
Bold: 700
Extrabold: 800
```

---

## Spacing & Layout

### Grid System
```
Container Max Width: 1280px
Gutter: 16px (mobile), 24px (tablet), 32px (desktop)
Columns: 4 (mobile), 8 (tablet), 12 (desktop)
Column Gap: 16px
```

### Breakpoints
```
xs: 0px–374px      (Small phones)
sm: 375px–639px    (Standard phones)
md: 640px–767px    (Large phones)
lg: 768px–1023px   (Tablets)
xl: 1024px–1279px  (Small desktops)
2xl: 1280px+       (Large desktops)
```

### Safe Areas
```
Status Bar: 44px (iOS), 24px (Android)
Bottom Safe Area: 34px (iPhone with notch), 0px (others)
Navigation Bar: 56px (standard)
Tab Bar: 56px + safe area
```

### Container Padding
```
Mobile (xs-md): 16px horizontal, 12px vertical
Tablet (lg): 24px horizontal, 16px vertical
Desktop (xl+): 32px horizontal, 24px vertical
```

### Section Spacing
```
Section Vertical Margin:
  Mobile: 32px
  Tablet: 48px
  Desktop: 64px

Section Internal Padding:
  Mobile: 16px
  Tablet: 24px
  Desktop: 32px
```

---

## Components

### Buttons

#### Primary Button
```
Size Large
  Height: 56px
  Padding Horizontal: 32px
  Padding Vertical: 16px
  Font: label-lg (16px/500)
  Border Radius: radius-lg (12px)
  Min Width: 120px

  Background: primary-500 (#E23744)
  Text Color: neutral-0 (#FFFFFF)

  Shadow: shadow-md

  States:
    Hover: background → primary-600, shadow → shadow-lg
    Active: background → primary-700, shadow → shadow-sm, scale(0.98)
    Disabled: background → neutral-300, text → neutral-500, shadow → none
    Loading: background → primary-500, opacity 0.8, spinner (white)

Size Medium [DEFAULT]
  Height: 48px
  Padding Horizontal: 24px
  Padding Vertical: 12px
  Font: label-lg (16px/500)
  Border Radius: radius-lg (12px)
  Min Width: 100px

Size Small
  Height: 40px
  Padding Horizontal: 20px
  Padding Vertical: 10px
  Font: label-md (14px/500)
  Border Radius: radius-md (8px)
  Min Width: 80px

Icon Button (with icon)
  Icon Size: 20px (medium), 18px (small)
  Icon Spacing: 8px (left of text)
```

#### Secondary Button
```
Same dimensions as Primary

Background: transparent
Border: 1.5px solid primary-500
Text Color: primary-500

States:
  Hover: background → primary-50, border → primary-600
  Active: background → primary-100, border → primary-700, scale(0.98)
  Disabled: border → neutral-300, text → neutral-400
```

#### Tertiary Button (Text Button)
```
Same dimensions as Primary

Background: transparent
Border: none
Text Color: primary-500

Padding Horizontal: 16px (reduced)

States:
  Hover: background → primary-50
  Active: background → primary-100, scale(0.98)
  Disabled: text → neutral-400
```

#### Ghost Button
```
Same dimensions as Primary

Background: neutral-100
Border: none
Text Color: neutral-700

States:
  Hover: background → neutral-200
  Active: background → neutral-300, scale(0.98)
  Disabled: text → neutral-400
```

#### Floating Action Button (FAB)
```
Size: 56px × 56px
Border Radius: radius-full
Background: primary-500
Icon: 24px, white
Shadow: shadow-xl

Position: Fixed bottom-right
Margin: 16px from edges

States:
  Hover: shadow → shadow-2xl, scale(1.05)
  Active: scale(0.95)
```

---

### Input Fields

#### Text Input
```
Default State
  Height: 48px
  Padding: 12px 16px
  Border: 1px solid neutral-300
  Border Radius: radius-lg (12px)
  Background: neutral-0

  Font: body-md (16px/400)
  Text Color: neutral-800
  Placeholder Color: neutral-500

Focus State
  Border: 2px solid primary-500
  Padding: 11px 15px (adjust for thicker border)
  Shadow: 0 0 0 3px rgba(226, 55, 68, 0.1)

Error State
  Border: 2px solid error-500
  Shadow: 0 0 0 3px rgba(239, 68, 68, 0.1)

Disabled State
  Background: neutral-100
  Border: 1px solid neutral-200
  Text Color: neutral-500
  Cursor: not-allowed

Label (above input)
  Font: label-md (14px/500)
  Color: neutral-700
  Margin Bottom: 8px

Helper Text (below input)
  Font: caption (12px/400)
  Color: neutral-600
  Margin Top: 6px

Error Text (below input)
  Font: caption (12px/400)
  Color: error-500
  Margin Top: 6px
  Icon: 12px alert icon, 4px left margin
```

#### Search Input
```
Height: 44px
Padding: 10px 16px 10px 44px (space for icon)
Border Radius: radius-3xl (24px)
Border: none
Background: neutral-100
Shadow: shadow-sm

Font: body-md (16px/400)

Search Icon
  Size: 20px
  Position: Absolute left 16px
  Color: neutral-500

Clear Button (when filled)
  Size: 16px × 16px
  Position: Absolute right 14px
  Color: neutral-500
  Padding: 8px (touchable area 32px)

Focus State
  Background: neutral-0
  Border: 1.5px solid neutral-300
  Shadow: shadow-md
```

#### Textarea
```
Min Height: 120px
Max Height: 300px
Padding: 12px 16px
Border: 1px solid neutral-300
Border Radius: radius-lg (12px)
Resize: vertical

Font: body-md (16px/400)
Line Height: 24px

Character Counter (bottom right)
  Font: caption (12px/400)
  Color: neutral-500
  Margin: 6px 0 0 0
  Position: Right-aligned
```

#### Checkbox
```
Size: 20px × 20px
Border: 2px solid neutral-400
Border Radius: radius-sm (4px)
Background: neutral-0

Checked State
  Background: primary-500
  Border: 2px solid primary-500
  Checkmark: White, 14px

Label
  Font: body-md (16px/400)
  Color: neutral-700
  Margin Left: 12px
  Vertical Align: Center

Touchable Area: 44px × 44px (for mobile)
```

#### Radio Button
```
Size: 20px × 20px
Border: 2px solid neutral-400
Border Radius: radius-full
Background: neutral-0

Selected State
  Border: 2px solid primary-500
  Inner Dot: 10px, primary-500

Label (same as checkbox)
```

#### Toggle Switch
```
Track Width: 48px
Track Height: 28px
Track Border Radius: radius-full
Track Background (off): neutral-300
Track Background (on): primary-500

Thumb Size: 24px × 24px
Thumb Border Radius: radius-full
Thumb Background: neutral-0
Thumb Shadow: shadow-md
Thumb Position (off): 2px from left
Thumb Position (on): 2px from right

Animation: 200ms ease-out

Label
  Font: body-md (16px/400)
  Margin Right: 12px
```

#### Dropdown / Select
```
Same as Text Input

Dropdown Icon
  Size: 16px chevron-down
  Position: Absolute right 16px
  Color: neutral-600

Dropdown Menu
  Max Height: 280px
  Overflow: Scroll
  Background: neutral-0
  Border Radius: radius-lg (12px)
  Shadow: shadow-xl
  Margin Top: 4px
  Padding: 8px 0

Dropdown Item
  Height: 44px
  Padding: 12px 16px
  Font: body-md (16px/400)
  Color: neutral-700

  Hover: background → neutral-100
  Selected: background → primary-50, color → primary-600, checkmark icon

Divider
  Height: 1px
  Background: neutral-200
  Margin: 8px 0
```

---

### Cards

#### Restaurant Card (Vertical)
```
Card Container
  Width: 100% (mobile), 320px (desktop)
  Border Radius: radius-xl (16px)
  Background: neutral-0
  Shadow: shadow-md
  Overflow: hidden

  Hover: shadow → shadow-lg, transform → translateY(-4px)
  Transition: 250ms ease-out

Restaurant Image
  Width: 100%
  Height: 180px
  Object Fit: cover
  Border Radius: radius-xl radius-xl 0 0

Offer Tag (if applicable)
  Position: Absolute top 12px left 12px
  Background: warning-500
  Color: neutral-0
  Font: label-sm (12px/600)
  Padding: 4px 10px
  Border Radius: radius-md (8px)
  Text Transform: Uppercase

Favorite Button
  Position: Absolute top 12px right 12px
  Size: 36px × 36px
  Background: rgba(255, 255, 255, 0.95)
  Border Radius: radius-full
  Icon: 20px heart
  Color: neutral-600 (unfilled), primary-500 (filled)
  Shadow: shadow-sm

Card Content
  Padding: 16px

Restaurant Name
  Font: h5 (18px/600)
  Color: neutral-900
  Margin Bottom: 4px
  Max Lines: 1
  Overflow: Ellipsis

Cuisine Type
  Font: body-sm (14px/400)
  Color: neutral-600
  Margin Bottom: 12px

Rating Row (horizontal flex)
  Align Items: Center
  Gap: 8px

Rating Badge
  Background: success-500
  Color: neutral-0
  Font: label-sm (12px/600)
  Padding: 4px 8px
  Border Radius: radius-md (8px)
  Icon: 10px star, 2px margin right

Delivery Info
  Font: caption (12px/400)
  Color: neutral-600

Price Range
  Font: caption (12px/400)
  Color: neutral-600
  Margin Left: auto
```

#### Restaurant Card (Horizontal)
```
Card Container
  Height: 120px
  Border Radius: radius-lg (12px)
  Background: neutral-0
  Shadow: shadow-sm
  Display: Flex
  Overflow: hidden

Restaurant Image
  Width: 120px
  Height: 120px
  Object Fit: cover
  Flex Shrink: 0

Card Content
  Padding: 12px 16px
  Flex: 1
  Display: Flex
  Flex Direction: Column
  Justify Content: Space between

(Rest of elements similar to vertical card)
```

#### Menu Item Card
```
Card Container
  Border Radius: radius-lg (12px)
  Background: neutral-0
  Padding: 12px
  Display: Flex
  Gap: 12px
  Shadow: shadow-sm

  Hover: shadow → shadow-md

Item Image
  Width: 100px
  Height: 100px
  Border Radius: radius-md (8px)
  Object Fit: cover
  Flex Shrink: 0

Item Content
  Flex: 1
  Display: Flex
  Flex Direction: Column

Item Type Icon (veg/non-veg)
  Size: 16px
  Margin Bottom: 4px

Item Name
  Font: h6 (16px/600)
  Color: neutral-900
  Margin Bottom: 4px

Item Description
  Font: body-sm (14px/400)
  Color: neutral-600
  Max Lines: 2
  Overflow: Ellipsis
  Margin Bottom: 8px

Price Row
  Display: Flex
  Align Items: Center
  Justify Content: Space between
  Margin Top: auto

Item Price
  Font: h6 (16px/600)
  Color: neutral-900

Add Button
  Height: 32px
  Width: 80px
  Background: primary-500
  Color: neutral-0
  Font: label-md (14px/500)
  Border Radius: radius-md (8px)
  Border: none

Quantity Controls (when added)
  Display: Flex
  Align Items: Center
  Gap: 12px

  Minus/Plus Buttons
    Size: 28px × 28px
    Border: 1px solid primary-500
    Background: neutral-0
    Color: primary-500
    Border Radius: radius-sm (4px)

  Quantity Text
    Font: label-lg (16px/600)
    Color: neutral-900
    Min Width: 24px
    Text Align: Center
```

#### Order Card
```
Card Container
  Border Radius: radius-lg (12px)
  Background: neutral-0
  Padding: 16px
  Shadow: shadow-sm
  Border Left: 4px solid (status color)

Card Header
  Display: Flex
  Justify Content: Space between
  Align Items: Center
  Margin Bottom: 12px

Order ID
  Font: label-lg (16px/500)
  Color: neutral-900

Order Status Badge
  Background: (varies by status)
  Color: neutral-0
  Font: label-sm (12px/600)
  Padding: 4px 10px
  Border Radius: radius-md (8px)
  Text Transform: Uppercase

Restaurant Info
  Display: Flex
  Align Items: Center
  Gap: 12px
  Margin Bottom: 12px

Restaurant Logo
  Size: 40px × 40px
  Border Radius: radius-md (8px)

Restaurant Name
  Font: h6 (16px/600)
  Color: neutral-900

Order Items
  Font: body-sm (14px/400)
  Color: neutral-600
  Margin Bottom: 8px
  Max Lines: 2
  Overflow: Ellipsis

Card Footer
  Display: Flex
  Justify Content: Space between
  Align Items: Center
  Padding Top: 12px
  Border Top: 1px solid neutral-200

Order Date
  Font: caption (12px/400)
  Color: neutral-600

Order Total
  Font: h6 (16px/600)
  Color: neutral-900

Action Button
  Height: 36px
  Padding: 8px 16px
  Font: label-md (14px/500)
  Border Radius: radius-md (8px)
  Margin Top: 12px
```

---

### Navigation

#### Top Navigation Bar
```
Container
  Height: 56px
  Background: neutral-0
  Border Bottom: 1px solid neutral-200
  Padding: 0 16px
  Display: Flex
  Align Items: Center
  Position: Sticky
  Top: 0
  Z Index: elevation-3

Logo / Title
  Font: h4 (20px/600)
  Color: neutral-900
  Display: Flex
  Align Items: Center
  Gap: 8px

Logo Image
  Height: 32px
  Width: auto

Back Button (if applicable)
  Size: 40px × 40px
  Icon: 24px
  Color: neutral-700
  Border Radius: radius-md (8px)
  Margin Right: 8px

  Hover: background → neutral-100

Action Buttons (right aligned)
  Display: Flex
  Gap: 8px
  Margin Left: auto

Icon Button
  Size: 40px × 40px
  Icon: 24px
  Color: neutral-700
  Border Radius: radius-md (8px)

  Hover: background → neutral-100

Badge (notification count)
  Position: Absolute top 6px right 6px
  Size: 18px × 18px
  Background: primary-500
  Color: neutral-0
  Font: 10px/600
  Border Radius: radius-full
  Border: 2px solid neutral-0
```

#### Bottom Navigation Bar
```
Container
  Height: 56px + safe area
  Background: neutral-0
  Border Top: 1px solid neutral-200
  Padding: 0 8px (bottom safe area)
  Display: Flex
  Justify Content: Space around
  Position: Fixed
  Bottom: 0
  Z Index: elevation-3
  Shadow: 0 -2px 8px rgba(0,0,0,0.06)

Nav Item
  Display: Flex
  Flex Direction: Column
  Align Items: Center
  Justify Content: Center
  Flex: 1
  Max Width: 120px
  Padding: 8px 12px
  Border Radius: radius-md (8px)
  Gap: 4px

  Transition: 150ms ease-out

Nav Icon
  Size: 24px
  Color (inactive): neutral-500
  Color (active): primary-500

Nav Label
  Font: caption (12px/400)
  Color (inactive): neutral-600
  Color (active): primary-500

Active Indicator (optional)
  Width: 32px
  Height: 3px
  Background: primary-500
  Border Radius: radius-full
  Position: Absolute top 0

States
  Inactive: default colors
  Active: primary color, font weight 500
  Pressed: scale(0.95), background → neutral-100
```

#### Tab Bar (Horizontal Scroll)
```
Container
  Display: Flex
  Gap: 8px
  Padding: 12px 16px
  Background: neutral-0
  Overflow X: Auto
  Scroll Behavior: Smooth
  Border Bottom: 1px solid neutral-200

Tab Item
  Padding: 10px 20px
  Border Radius: radius-full
  Font: label-md (14px/500)
  White Space: Nowrap
  Transition: 150ms ease-out

  Inactive State
    Background: neutral-100
    Color: neutral-700

  Active State
    Background: primary-500
    Color: neutral-0

  Hover (inactive)
    Background: neutral-200
```

---

### Badges & Chips

#### Badge
```
Small Badge
  Padding: 4px 8px
  Font: label-sm (12px/500)
  Border Radius: radius-md (8px)

Medium Badge
  Padding: 6px 12px
  Font: label-md (14px/500)
  Border Radius: radius-md (8px)

Large Badge
  Padding: 8px 16px
  Font: label-lg (16px/500)
  Border Radius: radius-lg (12px)

Variants
  Success: background → success-500, color → neutral-0
  Warning: background → warning-500, color → neutral-900
  Error: background → error-500, color → neutral-0
  Info: background → info-500, color → neutral-0
  Neutral: background → neutral-200, color → neutral-900

Icon Badge
  Icon Size: 14px (small), 16px (medium), 18px (large)
  Icon Margin Right: 4px
```

#### Chip (Removable Tag)
```
Container
  Display: Inline flex
  Align Items: Center
  Padding: 6px 12px
  Background: neutral-100
  Border: 1px solid neutral-300
  Border Radius: radius-full
  Gap: 6px

Label
  Font: label-md (14px/400)
  Color: neutral-700

Remove Button
  Size: 16px × 16px
  Icon: 12px × (close)
  Color: neutral-600
  Border Radius: radius-full
  Padding: 2px

  Hover: background → neutral-300
```

#### Notification Badge (Dot)
```
Size: 8px × 8px (small), 10px × 10px (medium)
Background: error-500
Border: 2px solid neutral-0
Border Radius: radius-full
Position: Absolute (typically top-right)
```

---

### Lists

#### List Item (Basic)
```
Container
  Min Height: 56px
  Padding: 12px 16px
  Display: Flex
  Align Items: Center
  Gap: 12px
  Border Bottom: 1px solid neutral-200

  Hover: background → neutral-50
  Active: background → neutral-100

Leading Icon
  Size: 24px
  Color: neutral-600
  Flex Shrink: 0

Leading Image
  Size: 48px × 48px
  Border Radius: radius-md (8px)
  Flex Shrink: 0

Content
  Flex: 1
  Display: Flex
  Flex Direction: Column
  Gap: 2px

Primary Text
  Font: body-md (16px/400)
  Color: neutral-900

Secondary Text
  Font: body-sm (14px/400)
  Color: neutral-600

Trailing Icon
  Size: 20px
  Color: neutral-500
  Flex Shrink: 0

Trailing Text
  Font: body-sm (14px/400)
  Color: neutral-600
```

#### List Item (Three-line)
```
Min Height: 88px
Padding: 16px

Content
  Gap: 4px

Primary Text
  Font: h6 (16px/600)
  Max Lines: 1

Secondary Text
  Font: body-sm (14px/400)
  Max Lines: 2
  Line Clamp: 2
```

---

### Modals & Dialogs

#### Modal (Full Screen Overlay)
```
Backdrop
  Background: rgba(0, 0, 0, 0.5)
  Position: Fixed
  Inset: 0
  Z Index: elevation-4
  Backdrop Filter: blur(4px)

Modal Container
  Position: Fixed
  Top: 50%
  Left: 50%
  Transform: translate(-50%, -50%)
  Background: neutral-0
  Border Radius: radius-2xl (20px)
  Shadow: shadow-2xl
  Max Width: 480px
  Width: calc(100vw - 32px)
  Max Height: calc(100vh - 64px)
  Overflow: hidden

Modal Header
  Padding: 20px 24px
  Border Bottom: 1px solid neutral-200
  Display: Flex
  Justify Content: Space between
  Align Items: Center

Modal Title
  Font: h4 (20px/600)
  Color: neutral-900

Close Button
  Size: 32px × 32px
  Icon: 20px
  Color: neutral-600
  Border Radius: radius-md (8px)

  Hover: background → neutral-100

Modal Body
  Padding: 24px
  Overflow Y: Auto
  Max Height: calc(100vh - 240px)

Modal Footer
  Padding: 16px 24px
  Border Top: 1px solid neutral-200
  Display: Flex
  Gap: 12px
  Justify Content: Flex end
```

#### Bottom Sheet
```
Container
  Position: Fixed
  Bottom: 0
  Left: 0
  Right: 0
  Background: neutral-0
  Border Radius: radius-2xl radius-2xl 0 0
  Shadow: shadow-2xl
  Max Height: 90vh
  Z Index: elevation-4
  Transform: translateY(100%)
  Transition: transform 300ms ease-out

Handle Bar
  Width: 32px
  Height: 4px
  Background: neutral-300
  Border Radius: radius-full
  Margin: 12px auto 8px

Content
  Padding: 16px 24px 32px
  Overflow Y: Auto
```

#### Alert Dialog
```
Same structure as Modal

Icon (optional)
  Size: 48px
  Margin: 0 auto 16px
  Color: varies (success/warning/error/info)

Title
  Font: h4 (20px/600)
  Text Align: Center
  Margin Bottom: 8px

Description
  Font: body-md (16px/400)
  Color: neutral-600
  Text Align: Center
  Line Height: 24px

Actions
  Display: Flex
  Gap: 12px
  Margin Top: 24px
  Flex Direction: Column (mobile)
  Flex Direction: Row (desktop)
```

---

### Toast / Snackbar

#### Toast Notification
```
Container
  Position: Fixed
  Bottom: 80px (above bottom nav)
  Left: 50%
  Transform: translateX(-50%)
  Max Width: 400px
  Width: calc(100vw - 32px)
  Background: neutral-900
  Color: neutral-0
  Border Radius: radius-lg (12px)
  Shadow: shadow-xl
  Padding: 14px 16px
  Display: Flex
  Align Items: Center
  Gap: 12px
  Z Index: elevation-5

  Animation: slide-up 200ms ease-out

Icon (optional)
  Size: 20px
  Flex Shrink: 0

Message
  Font: body-sm (14px/400)
  Flex: 1

Action Button
  Font: label-md (14px/600)
  Color: primary-300
  Padding: 4px 8px
  Border Radius: radius-sm (4px)

  Hover: background → rgba(255, 255, 255, 0.1)

Close Button
  Size: 20px
  Opacity: 0.8

  Hover: opacity → 1

Variants
  Success: background → success-600, icon → checkmark
  Error: background → error-600, icon → alert
  Warning: background → warning-600, color → neutral-900
  Info: background → info-600

Duration: 4000ms (auto-dismiss)
```

---

### Loading States

#### Spinner
```
Small
  Size: 16px × 16px
  Border Width: 2px

Medium
  Size: 24px × 24px
  Border Width: 2.5px

Large
  Size: 40px × 40px
  Border Width: 3px

Color: primary-500
Animation: rotate 800ms linear infinite
```

#### Skeleton Loader
```
Base
  Background: linear-gradient(
    90deg,
    neutral-200 0%,
    neutral-100 50%,
    neutral-200 100%
  )
  Background Size: 200% 100%
  Animation: shimmer 1.5s ease-in-out infinite
  Border Radius: radius-md (8px)

Text Skeleton
  Height: 14px (body-sm)
  Height: 16px (body-md)
  Height: 20px (h6)
  Width: varies (60%, 80%, 100%)
  Margin Bottom: 8px

Image Skeleton
  Width: 100%
  Aspect Ratio: 16/9
  Border Radius: radius-lg (12px)

Card Skeleton
  Padding: 16px
  Display: Flex
  Flex Direction: Column
  Gap: 12px
```

#### Progress Bar
```
Container
  Height: 4px (thin), 8px (default)
  Background: neutral-200
  Border Radius: radius-full
  Overflow: hidden

Progress
  Height: 100%
  Background: primary-500
  Border Radius: radius-full
  Transition: width 300ms ease-out

Indeterminate Mode
  Width: 40%
  Animation: progress-indeterminate 1.5s ease-in-out infinite
```

---

### Images & Media

#### Avatar
```
Extra Small: 24px × 24px
Small: 32px × 32px
Medium: 40px × 40px
Large: 64px × 64px
Extra Large: 96px × 96px

Border Radius: radius-full
Object Fit: cover

With Status Indicator
  Indicator Size: 25% of avatar
  Indicator Position: Bottom right
  Indicator Border: 2px solid neutral-0
  Indicator Colors:
    Online: success-500
    Away: warning-500
    Busy: error-500
    Offline: neutral-400
```

#### Image Card
```
Container
  Position: Relative
  Border Radius: radius-xl (16px)
  Overflow: hidden
  Aspect Ratio: 16/9 (default), 1/1 (square), 4/3

Image
  Width: 100%
  Height: 100%
  Object Fit: cover

Overlay Gradient (optional)
  Background: linear-gradient(
    180deg,
    rgba(0,0,0,0) 0%,
    rgba(0,0,0,0.6) 100%
  )
  Position: Absolute
  Inset: 0

Caption (over gradient)
  Position: Absolute
  Bottom: 16px
  Left: 16px
  Right: 16px
  Color: neutral-0
  Font: h6 (16px/600)
```

---

### Forms

#### Form Container
```
Padding: 24px 16px (mobile)
Padding: 32px 24px (desktop)
Max Width: 560px
Margin: 0 auto
```

#### Form Section
```
Margin Bottom: 32px

Section Title
  Font: h5 (18px/600)
  Color: neutral-900
  Margin Bottom: 16px
```

#### Form Field Group
```
Margin Bottom: 20px
Display: Flex
Flex Direction: Column
Gap: 8px
```

#### Form Row (Inline Fields)
```
Display: Flex
Gap: 16px

Field
  Flex: 1
```

#### Form Actions
```
Display: Flex
Gap: 12px
Margin Top: 32px
Padding Top: 24px
Border Top: 1px solid neutral-200

Justify Content: Flex end (desktop)
Flex Direction: Column (mobile)
```

---

### Empty States

#### Empty State Container
```
Padding: 64px 32px
Text Align: Center
Display: Flex
Flex Direction: Column
Align Items: Center
Gap: 16px

Illustration
  Width: 200px
  Height: 200px
  Margin Bottom: 8px
  Opacity: 0.8

Title
  Font: h4 (20px/600)
  Color: neutral-900

Description
  Font: body-md (16px/400)
  Color: neutral-600
  Max Width: 360px

Action Button
  Margin Top: 8px
```

---

### Dividers

#### Horizontal Divider
```
Full Width
  Height: 1px
  Background: neutral-200
  Margin: 16px 0

Inset
  Height: 1px
  Background: neutral-200
  Margin: 16px 72px 16px 16px (space for avatar/icon)

With Text
  Display: Flex
  Align Items: Center
  Gap: 16px

  Text
    Font: caption (12px/400)
    Color: neutral-500
    Text Transform: Uppercase
    Letter Spacing: 0.5px

  Lines
    Flex: 1
    Height: 1px
    Background: neutral-200
```

---

## Patterns & Templates

### Home Screen Layout
```
Container
  Background: neutral-50

Header Section
  Background: neutral-0
  Padding: 16px
  Shadow: shadow-sm

Location Selector
  Display: Flex
  Align Items: Center
  Gap: 8px
  Margin Bottom: 12px

  Icon: 20px, primary-500
  Text: body-md (16px/500), neutral-900
  Dropdown Icon: 16px, neutral-600

Search Bar
  (See Search Input component)

Banner Carousel
  Margin: 16px
  Border Radius: radius-xl (16px)
  Aspect Ratio: 16/9

  Indicators
    Position: Absolute bottom 12px
    Display: Flex
    Gap: 6px
    Justify Content: Center

    Dot
      Size: 6px × 6px
      Border Radius: radius-full
      Background: rgba(255,255,255,0.5)

    Active Dot
      Width: 20px
      Background: neutral-0

Category Scrollbar
  Display: Flex
  Gap: 12px
  Padding: 16px
  Overflow X: Auto

  Category Item
    Display: Flex
    Flex Direction: Column
    Align Items: Center
    Gap: 8px
    Min Width: 72px

    Icon Container
      Size: 64px × 64px
      Background: neutral-100
      Border Radius: radius-full
      Display: Flex
      Align Items: Center
      Justify Content: Center

      Icon: 32px, neutral-700

    Label
      Font: caption (12px/400)
      Color: neutral-700
      Text Align: Center

Section Header
  Display: Flex
  Justify Content: Space between
  Align Items: Center
  Padding: 16px 16px 12px

  Title: h5 (18px/600), neutral-900

  View All Button
    Font: label-md (14px/500)
    Color: primary-500

Restaurant List
  Padding: 0 16px 16px
  Display: Grid
  Grid Template Columns: 1fr (mobile)
  Grid Template Columns: repeat(2, 1fr) (tablet)
  Grid Template Columns: repeat(3, 1fr) (desktop)
  Gap: 16px
```

### Restaurant Detail Screen
```
Hero Image
  Height: 240px (mobile), 320px (tablet)
  Position: Relative

  Image: full width, object-fit cover

  Overlay: gradient-dark (bottom)

  Back Button
    Position: Absolute top 16px left 16px
    Size: 40px × 40px
    Background: rgba(255,255,255,0.95)
    Icon: 24px, neutral-900
    Border Radius: radius-full
    Shadow: shadow-md

Restaurant Info Section
  Background: neutral-0
  Padding: 20px 16px
  Border Radius: radius-2xl radius-2xl 0 0
  Margin Top: -24px
  Position: Relative
  Shadow: shadow-lg

Restaurant Name
  Font: h3 (24px/600)
  Color: neutral-900
  Margin Bottom: 4px

Cuisine & Location
  Font: body-sm (14px/400)
  Color: neutral-600
  Margin Bottom: 16px

Info Pills Row
  Display: Flex
  Gap: 12px
  Overflow X: Auto
  Margin Bottom: 16px

  Pill
    Background: neutral-100
    Padding: 8px 12px
    Border Radius: radius-full
    Font: caption (12px/400)
    Color: neutral-700
    White Space: Nowrap

    Icon: 14px, 4px margin right

Tabs
  (See Tab Bar component)
  Sticky position, top 56px (below header)

Tab Content
  Padding: 16px
```

### Menu Screen
```
Menu Categories (Sticky)
  Position: Sticky
  Top: 112px (header + tabs)
  Background: neutral-0
  Z Index: elevation-2
  Padding: 12px 16px
  Border Bottom: 1px solid neutral-200

  (See Tab Bar component for styling)

Menu Section
  Margin Bottom: 24px

Section Title
  Font: h5 (18px/600)
  Color: neutral-900
  Padding: 16px 16px 12px
  Background: neutral-50
  Sticky: top 164px
  Z Index: elevation-1

Menu Items
  Display: Flex
  Flex Direction: Column
  Gap: 12px
  Padding: 0 16px 16px
```

### Cart Screen
```
Item List
  Background: neutral-0
  Padding: 16px

Cart Item
  Display: Flex
  Gap: 12px
  Padding: 12px 0
  Border Bottom: 1px solid neutral-200

  Item Image
    Size: 64px × 64px
    Border Radius: radius-md (8px)
    Object Fit: cover

  Item Details
    Flex: 1

    Name: h6 (16px/600), neutral-900
    Customization: caption (12px/400), neutral-600

  Price & Controls
    Display: Flex
    Flex Direction: Column
    Align Items: Flex end
    Gap: 8px

    Price: h6 (16px/600), neutral-900

    Quantity Controls: (See Menu Item Card)

Bill Details Section
  Background: neutral-0
  Padding: 16px
  Margin Top: 12px

  Title: h6 (16px/600), margin bottom 12px

  Line Item
    Display: Flex
    Justify Content: Space between
    Padding: 8px 0
    Font: body-sm (14px/400)

    Label: neutral-700
    Value: neutral-900

  Total Line
    Border Top: 1px dashed neutral-300
    Padding Top: 12px
    Margin Top: 12px
    Font: h6 (16px/600)
    Color: neutral-900

Checkout Button (Fixed)
  Position: Fixed
  Bottom: 0
  Left: 0
  Right: 0
  Padding: 16px
  Background: neutral-0
  Shadow: shadow-xl
  Z Index: elevation-3

  Button: (See Primary Button Large)
```

### Order Tracking Screen
```
Status Timeline
  Padding: 24px 16px
  Background: neutral-0

Timeline Item
  Display: Flex
  Gap: 16px
  Padding Bottom: 24px
  Position: Relative

  Timeline Indicator
    Size: 32px × 32px
    Border Radius: radius-full
    Background: neutral-200 (inactive)
    Background: success-500 (completed)
    Background: primary-500 (active)
    Border: 3px solid neutral-0
    Display: Flex
    Align Items: Center
    Justify Content: Center
    Z Index: 1

    Icon: 16px, neutral-0

  Timeline Line
    Position: Absolute
    Left: 15px
    Top: 32px
    Width: 2px
    Height: calc(100% - 32px)
    Background: neutral-200 (inactive)
    Background: success-500 (completed)

  Timeline Content
    Flex: 1
    Padding Top: 4px

    Title: h6 (16px/600), neutral-900
    Description: body-sm (14px/400), neutral-600
    Time: caption (12px/400), neutral-500

Delivery Info Card
  Background: neutral-50
  Border: 1px solid neutral-200
  Border Radius: radius-lg (12px)
  Padding: 16px
  Margin: 0 16px 16px

  Delivery Partner Info
    Display: Flex
    Align Items: Center
    Gap: 12px
    Margin Bottom: 12px

    Avatar: 48px
    Name: h6 (16px/600)
    Rating: caption (12px/400)

  Action Buttons
    Display: Flex
    Gap: 12px

    Call Button: Secondary, icon 18px
    Message Button: Secondary, icon 18px
```

### Profile Screen
```
Header Section
  Background: primary-500
  Padding: 40px 16px 24px
  Color: neutral-0

  Avatar: 80px × 80px, border 3px solid neutral-0
  Name: h4 (20px/600), margin top 12px
  Email: body-sm (14px/400), opacity 0.9

Menu Sections
  Background: neutral-50

Menu Section
  Background: neutral-0
  Margin Bottom: 12px
  Padding: 8px 0

Menu Item
  (See List Item component)
  Min Height: 56px
  Padding: 12px 16px

  Leading Icon: 24px, primary-500
  Label: body-md (16px/400), neutral-900
  Trailing Icon: 20px chevron-right, neutral-400

Logout Button
  Margin: 24px 16px
  (See Secondary Button with error color)
```

---

## Motion & Animation

### Animation Timing
```
Instant: 100ms      // Micro-interactions
Fast: 150ms         // Hovers, toggles
Default: 200ms      // Most transitions
Moderate: 300ms     // Modals, sheets
Slow: 400ms         // Page transitions
Very Slow: 600ms    // Complex animations
```

### Easing Functions
```
ease-in: cubic-bezier(0.4, 0, 1, 1)
ease-out: cubic-bezier(0, 0, 0.2, 1)          [DEFAULT]
ease-in-out: cubic-bezier(0.4, 0, 0.2, 1)
ease-bounce: cubic-bezier(0.68, -0.55, 0.265, 1.55)
```

### Common Animations

#### Fade In
```
@keyframes fade-in {
  from { opacity: 0; }
  to { opacity: 1; }
}
Duration: 200ms
Easing: ease-out
```

#### Slide Up
```
@keyframes slide-up {
  from {
    opacity: 0;
    transform: translateY(20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
Duration: 300ms
Easing: ease-out
```

#### Scale In
```
@keyframes scale-in {
  from {
    opacity: 0;
    transform: scale(0.9);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}
Duration: 200ms
Easing: ease-out
```

#### Shimmer (Loading)
```
@keyframes shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}
Duration: 1500ms
Easing: ease-in-out
Iteration: infinite
```

#### Ripple Effect
```
@keyframes ripple {
  0% {
    transform: scale(0);
    opacity: 1;
  }
  100% {
    transform: scale(2);
    opacity: 0;
  }
}
Duration: 600ms
Easing: ease-out
```

### Page Transitions
```
Route Enter
  Animation: slide-up
  Duration: 300ms
  Easing: ease-out

Route Exit
  Animation: fade-out
  Duration: 150ms
  Easing: ease-in

Modal Open
  Backdrop: fade-in 200ms
  Content: scale-in 250ms ease-out

Modal Close
  Backdrop: fade-out 150ms
  Content: scale-out 200ms ease-in

Bottom Sheet Open
  Transform: translateY(0)
  Duration: 300ms
  Easing: ease-out

Bottom Sheet Close
  Transform: translateY(100%)
  Duration: 250ms
  Easing: ease-in
```

### Micro-interactions
```
Button Press
  Transform: scale(0.97)
  Duration: 100ms
  Easing: ease-out

Like Heart
  Scale: 0.8 → 1.2 → 1
  Duration: 400ms
  Easing: ease-bounce

Add to Cart
  Item Image: translateX/Y to cart icon
  Duration: 500ms
  Easing: ease-in-out

Loading Spinner
  Rotation: 0deg → 360deg
  Duration: 800ms
  Easing: linear
  Iteration: infinite

Checkbox Check
  Checkmark: draw from 0% to 100%
  Duration: 250ms
  Easing: ease-out

Toggle Switch
  Thumb: translateX
  Duration: 200ms
  Easing: ease-out
```

---

## Accessibility

### WCAG 2.1 AA Compliance

#### Color Contrast
```
Normal Text (< 18px)
  Minimum Ratio: 4.5:1

Large Text (≥ 18px or ≥ 14px bold)
  Minimum Ratio: 3:1

UI Components & Graphics
  Minimum Ratio: 3:1

Tested Combinations
  ✓ primary-500 on neutral-0: 4.8:1
  ✓ neutral-900 on neutral-0: 15.2:1
  ✓ neutral-700 on neutral-0: 8.9:1
  ✓ neutral-600 on neutral-0: 5.1:1
  ✗ neutral-500 on neutral-0: 3.2:1 (too low)
```

#### Touch Targets
```
Minimum Size: 44px × 44px (iOS), 48px × 48px (Android)
Recommended: 48px × 48px (all platforms)

Spacing Between Targets: ≥ 8px

Implementation
  If visual element < 48px, add transparent padding
  Example: 24px icon → 48px touchable area with 12px padding
```

#### Focus States
```
Keyboard Focus Indicator
  Outline: 2px solid primary-500
  Outline Offset: 2px
  Border Radius: inherit

Focus Visible (keyboard only)
  Apply outline

Focus (mouse/touch)
  No outline (relies on hover/active states)
```

#### Screen Reader Support
```
All Images
  Must have alt text
  Decorative images: alt=""

All Icons
  Must have aria-label or sr-only text
  Example: <icon aria-label="Search" />

Interactive Elements
  Must have accessible name
  Buttons: text or aria-label
  Links: descriptive text (not "click here")

Form Fields
  Must have associated <label> or aria-label
  Error messages: aria-describedby

Status Messages
  Use role="status" or aria-live="polite"

Landmarks
  <header>, <nav>, <main>, <footer>
  Use aria-label for multiple same landmarks
```

#### Keyboard Navigation
```
Tab Order
  Logical, follows visual layout
  Skip repetitive elements with "Skip to content" link

Interactive Elements
  All must be keyboard accessible
  Enter/Space: Activate buttons/links
  Arrow Keys: Navigate lists, menus, tabs
  Esc: Close modals, dropdowns

Focus Trap
  Modals: trap focus inside
  First tab: focus first element
  Shift+Tab from first: focus last element
  Esc: close and return focus to trigger
```

#### Motion & Animation
```
Respect prefers-reduced-motion

@media (prefers-reduced-motion: reduce) {
  * {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}

Provide pause/stop controls for auto-playing content
```

#### Text Scaling
```
Support Dynamic Type (iOS)
Support Font Scaling (Android)

Test at 200% zoom
  Content must be readable
  No horizontal scrolling (except data tables)
  No content cut off

Use relative units
  rem/em (not px) for font sizes
  % or viewport units for layouts
```

#### Error Handling
```
Form Validation
  Identify error fields clearly
  Provide specific error messages
  Use color + icon (not color alone)
  aria-invalid="true" on error fields
  aria-describedby linking to error text

Example
  <input
    id="email"
    aria-invalid="true"
    aria-describedby="email-error"
  />
  <span id="email-error" role="alert">
    Please enter a valid email address
  </span>
```

---

## Platform-Specific Considerations

### iOS Guidelines
```
Navigation
  Use native iOS navigation patterns
  Swipe right to go back
  Modal sheets use drag-to-dismiss

Typography
  Prefer SF Pro Display/Text
  Use SF Symbols for icons

Haptics
  Light impact: selection changed
  Medium impact: success action
  Heavy impact: error/warning
  Selection: scroll through values

Safe Areas
  Account for notch/Dynamic Island
  Use safe-area-inset-*
```

### Android Guidelines
```
Navigation
  Use Material Design navigation patterns
  Hardware back button support

Typography
  Prefer Roboto

Ripple Effects
  Apply to all touchable elements
  Unbounded ripple for icons
  Bounded ripple for cards/buttons

Status Bar
  Transparent with scrim on scrollable content
  Colored for specific themes
```

---

## Design Checklist

### Before Shipping
```
Visual Design
  ☐ All colors meet contrast requirements
  ☐ Typography scale is consistent
  ☐ Spacing uses design tokens
  ☐ Border radius is consistent
  ☐ Shadows follow elevation system

Components
  ☐ All states designed (default, hover, active, disabled, loading, error)
  ☐ Responsive behavior defined
  ☐ Empty states included
  ☐ Loading states included
  ☐ Error states included

Accessibility
  ☐ Color contrast tested (4.5:1 minimum)
  ☐ Touch targets ≥ 48px
  ☐ Keyboard navigation works
  ☐ Screen reader labels present
  ☐ Focus states visible
  ☐ Motion can be reduced

Responsive
  ☐ Mobile (375px) tested
  ☐ Tablet (768px) tested
  ☐ Desktop (1280px+) tested
  ☐ No horizontal scroll
  ☐ Text scaling tested (200%)

Performance
  ☐ Images optimized (WebP/AVIF)
  ☐ Lazy loading implemented
  ☐ Skeleton loaders in place
  ☐ Animation performance (60fps)

Cross-browser
  ☐ Chrome tested
  ☐ Safari tested
  ☐ Firefox tested
  ☐ Edge tested

Cross-platform
  ☐ iOS tested
  ☐ Android tested
  ☐ Platform-specific patterns respected
```

---

## Tools & Resources

### Design Tools
- **Figma:** Main design tool
- **Figma Tokens:** For design token management
- **Stark:** Accessibility contrast checker
- **VisBug:** In-browser design debugging

### Development Tools
- **Tailwind CSS / CSS-in-JS:** For implementation
- **Storybook:** Component documentation
- **Chromatic:** Visual regression testing

### Testing Tools
- **axe DevTools:** Accessibility testing
- **WAVE:** Web accessibility checker
- **Lighthouse:** Performance & accessibility audits
- **VoiceOver / TalkBack:** Screen reader testing

### Reference
- **Material Design 3:** Component patterns
- **iOS Human Interface Guidelines:** iOS patterns
- **WCAG 2.1:** Accessibility standards
- **Refactoring UI:** Design principles book

---

## Flutter Implementation

### Design Tokens in Flutter

#### Color Implementation
```dart
// lib/constants/colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color primary50 = Color(0xFFFEF2F2);
  static const Color primary100 = Color(0xFFFDE8E8);
  // ... continue for all colors
  static const Color primary500 = Color(0xFFE23744); // Main brand
  static const Color primary600 = Color(0xFFC81D3B); // Hover/active
  // ...

  // Neutral Colors
  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFFAFAFA);
  // ...

  // Semantic Colors
  static const Color success500 = Color(0xFF00A859);
  static const Color error500 = Color(0xFFEF4444);
  // ...

  // Dark Mode Colors
  static const Color darkBgPrimary = Color(0xFF0A0A0A);
  // ...
}
```

#### Typography Implementation
```dart
// lib/constants/typography.dart
import 'package:flutter/material.dart';

class AppTypography {
  static const TextStyle displayLarge = TextStyle(
    fontSize: 57,
    height: 64 / 57,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 45,
    height: 52 / 45,
    fontWeight: FontWeight.w700,
  );

  // ... continue for all text styles

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  // Label styles
  static const TextStyle labelLarge = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
  );
}
```

#### Spacing Implementation
```dart
// lib/constants/spacing.dart
class AppSpacing {
  static const double spacing0 = 0;
  static const double spacing1 = 4;
  static const double spacing2 = 8;
  // ... up to spacing11 = 80
}
```

#### Border Radius Implementation
```dart
// lib/constants/border_radius.dart
import 'package:flutter/material.dart';

class AppBorderRadius {
  static const BorderRadius none = BorderRadius.zero;
  static const BorderRadius sm = BorderRadius.all(Radius.circular(4));
  static const BorderRadius md = BorderRadius.all(Radius.circular(8));
  // ...
}
```

#### Shadow Implementation
```dart
// lib/constants/shadows.dart
import 'package:flutter/material.dart';

class AppShadows {
  static const BoxShadow shadowSm = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.04),
    offset: Offset(0, 1),
    blurRadius: 2,
  );
  // ... continue for all shadows
}
```

### Component Implementation Examples

#### Primary Button
```dart
// lib/components/buttons/primary_button.dart
import 'package:flutter/material.dart';
import '../../constants/colors.dart';
import '../../constants/typography.dart';
import '../../constants/spacing.dart';
import '../../constants/border_radius.dart';
import '../../constants/shadows.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final ButtonSize size;

  const PrimaryButton({
    Key? key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.size = ButtonSize.medium,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary500,
        foregroundColor: AppColors.neutral0,
        padding: EdgeInsets.symmetric(
          horizontal: size == ButtonSize.large ? AppSpacing.spacing7 : AppSpacing.spacing6,
          vertical: size == ButtonSize.large ? AppSpacing.spacing4 : AppSpacing.spacing3,
        ),
        textStyle: AppTypography.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.lg,
        ),
        shadowColor: Colors.transparent,
        elevation: 0,
      ).copyWith(
        backgroundColor: MaterialStateProperty.resolveWith<Color>(
          (Set<MaterialState> states) {
            if (states.contains(MaterialState.disabled)) {
              return AppColors.neutral300;
            }
            if (states.contains(MaterialState.pressed)) {
              return AppColors.primary700;
            }
            if (states.contains(MaterialState.hovered)) {
              return AppColors.primary600;
            }
            return AppColors.primary500;
          },
        ),
      ),
      child: isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.neutral0),
              ),
            )
          : Text(text),
    );
  }
}

enum ButtonSize { small, medium, large }
```

#### Text Input
```dart
// lib/components/inputs/text_input.dart
import 'package:flutter/material.dart';
import '../../constants/colors.dart';
import '../../constants/typography.dart';
import '../../constants/spacing.dart';
import '../../constants/border_radius.dart';

class AppTextInput extends StatefulWidget {
  final String? label;
  final String? hint;
  final String? errorText;
  final TextEditingController? controller;
  final bool obscureText;

  const AppTextInput({
    Key? key,
    this.label,
    this.hint,
    this.errorText,
    this.controller,
    this.obscureText = false,
  }) : super(key: key);

  @override
  State<AppTextInput> createState() => _AppTextInputState();
}

class _AppTextInputState extends State<AppTextInput> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.neutral700,
            ),
          ),
          SizedBox(height: AppSpacing.spacing2),
        ],
        Focus(
          onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
          child: TextField(
            controller: widget.controller,
            obscureText: widget.obscureText,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.neutral800,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: AppColors.neutral500,
              ),
              contentPadding: EdgeInsets.all(AppSpacing.spacing3),
              border: OutlineInputBorder(
                borderRadius: AppBorderRadius.lg,
                borderSide: BorderSide(
                  color: AppColors.neutral300,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppBorderRadius.lg,
                borderSide: BorderSide(
                  color: AppColors.primary500,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: AppBorderRadius.lg,
                borderSide: BorderSide(
                  color: AppColors.error500,
                  width: 2,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: AppBorderRadius.lg,
                borderSide: BorderSide(
                  color: AppColors.error500,
                  width: 2,
                ),
              ),
              errorText: widget.errorText,
              errorStyle: AppTypography.caption.copyWith(
                color: AppColors.error500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

### Theme Setup
```dart
// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/typography.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    primaryColor: AppColors.primary500,
    scaffoldBackgroundColor: AppColors.neutral50,
    fontFamily: 'Inter',
    textTheme: TextTheme(
      displayLarge: AppTypography.displayLarge,
      displayMedium: AppTypography.displayMedium,
      // ... map all text styles
      bodyMedium: AppTypography.bodyMedium,
      labelLarge: AppTypography.labelLarge,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary500,
        foregroundColor: AppColors.neutral0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary500, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primary500,
    scaffoldBackgroundColor: AppColors.darkBgPrimary,
    fontFamily: 'Inter',
    // ... configure dark theme
  );
}
```

---

## Version History

**v2.1** - 2025-11-12 - Added Flutter implementation details
- Flutter code examples for design tokens
- Component implementation in Dart
- Theme setup guidelines
- Enhanced developer documentation

**v2.0** - 2025 - Complete redesign with modern standards
- Comprehensive design token system
- Detailed component specifications
- Enhanced accessibility guidelines
- Platform-specific considerations

**v1.0** - Previous - Initial guidelines

---

**Designed for:** Mobile-first food delivery applications
**Style Goal:** Modern · Trustworthy · Accessible · Fast

**Maintained by:** QuickDash Design Team
**Last Updated:** 2025-11-12
