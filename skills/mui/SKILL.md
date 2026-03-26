---
name: mui
description: Material-UI v6 component library patterns including sx prop styling, theme integration, responsive design, and MUI-specific hooks.
user-invocable: true
---

# MUI v6 Patterns

## Quick Start

```typescript
import { Box, Typography, Button, Paper } from '@mui/material';
import type { SxProps, Theme } from '@mui/material';

const styles: Record<string, SxProps<Theme>> = {
  container: { p: 2, display: 'flex', flexDirection: 'column', gap: 2 },
  header: { mb: 3, fontSize: '1.5rem', fontWeight: 600 },
};

function MyComponent() {
  return (
    <Paper sx={styles.container}>
      <Typography sx={styles.header}>Title</Typography>
      <Button variant="contained">Action</Button>
    </Paper>
  );
}
```

## Styling Rules

- DO type sx props: `const styles: Record<string, SxProps<Theme>> = { ... }`
- DO use theme tokens: `color: 'primary.main'`, `p: 2`, `bgcolor: 'background.paper'`
- DO use spacing scale: `p: 2`, `mb: 3`, `mt: 1`
- DO NOT hardcode colors: `color: '#1976d2'` → use `color: 'primary.main'`
- DO NOT hardcode spacing: `padding: '17px'` → use `p: 2`

### File Organization

- **< 100 lines**: define `styles` object at top of component file
- **>= 100 lines**: extract to `ComponentName.styles.ts`

```typescript
// UserProfile.styles.ts
import type { SxProps, Theme } from '@mui/material';
export const userProfileStyles: Record<string, SxProps<Theme>> = {
  container: { p: 3, maxWidth: 800, mx: 'auto' },
};

// UserProfile.tsx
import { userProfileStyles as styles } from './UserProfile.styles';
```

## Theme Integration

```typescript
// Direct tokens in sx
<Box sx={{ color: 'primary.main', bgcolor: 'background.paper', p: 2 }} />

// Callback for advanced usage
<Box sx={(theme) => ({
  color: theme.palette.primary.main,
  '&:hover': { color: theme.palette.primary.dark },
})} />

// useTheme hook
const theme = useTheme();
```

## Responsive Design

```typescript
// Mobile-first responsive values
<Box sx={{
  width: { xs: '100%', sm: '80%', md: '60%', lg: '40%' },
  display: { xs: 'none', md: 'block' },
}} />
```

Breakpoints: `xs` (0-600), `sm` (600-900), `md` (900-1200), `lg` (1200-1536), `xl` (1536+)

## Grid System

```typescript
import { Grid } from '@mui/material';

<Grid container spacing={2}>
  <Grid item xs={12} md={6}>Left</Grid>
  <Grid item xs={12} md={6}>Right</Grid>
</Grid>
```

## Forms

```typescript
<TextField
  label="Email"
  type="email"
  value={email}
  onChange={(e) => setEmail(e.target.value)}
  fullWidth
  required
  error={!!errors.email}
  helperText={errors.email}
/>
```

## Semantic Colors

- Primary: `primary.main`, `primary.light`, `primary.dark`
- Secondary: `secondary.main`, `error.main`, `warning.main`
- Text: `text.primary`, `text.secondary`
- Background: `background.paper`, `background.default`

## Icons

```typescript
import { Add as AddIcon, Delete as DeleteIcon } from '@mui/icons-material';

<Button startIcon={<AddIcon />}>Add</Button>
<IconButton onClick={handleDelete}><DeleteIcon /></IconButton>
```

## References

- `resources/styling-guide.md` — advanced styling patterns
- `resources/component-library.md` — Card, Dialog, Loading, extended component examples
- `resources/theme-customization.md` — theme setup and customization
