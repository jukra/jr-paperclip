# Migrating to the libvips Backend

Paperclip now supports [libvips](https://www.libvips.org/) via the `image_processing` gem. libvips is significantly faster and uses much less memory than ImageMagick, making it highly recommended for production environments.

This guide explains how to migrate your application to use libvips, either globally or gradually.

## Prerequisites

You must install the libvips system library on your server or development machine:

```bash
# macOS
brew install vips

# Ubuntu/Debian
sudo apt install libvips
```

## Step 1: Update your Gemfile

`jr-paperclip` already includes the `image_processing` gem, which automatically provides the `ruby-vips` and `mini_magick` bindings. You do **not** need to add these gems explicitly to your `Gemfile`.

Ensure you are using the latest version of the gem:

```ruby
gem "jr-paperclip", "~> 8.0.0.beta"
```

## Step 2: Gradual Migration (Per-Attachment)

The safest way to migrate is one attachment at a time. This allows you to verify that the output remains consistent and doesn't interfere with existing custom processors.

Simply add the `backend: :vips` option to a specific attachment:

```ruby
class User < ActiveRecord::Base
  has_attached_file :avatar,
    styles: { medium: "300x300>", thumb: "100x100#" },
    backend: :vips
end
```

Other attachments in your application will continue to use ImageMagick by default.

## Step 3: Cross-Platform Convert Options

Good news! Many common `convert_options` now work with **both** ImageMagick and libvips backends. You can keep using them as-is:

### Options That Work on Both Backends

| Option | Description |
|--------|-------------|
| `-strip` | Remove metadata/EXIF data |
| `-quality N` | Output quality (1-100) |
| `-rotate N` | Rotate by degrees |
| `-flip` | Vertical flip |
| `-flop` | Horizontal flip |
| `-blur 0xN` | Gaussian blur |
| `-sharpen 0xN` | Sharpen image |
| `-colorspace X` | Color space (Gray, sRGB, CMYK) |
| `-negate` | Invert colors |
| `-flatten` | Flatten transparency |
| `-auto-orient` | Auto-rotate via EXIF |
| `-interlace X` | Progressive/interlaced output |

**Example:**
```ruby
has_attached_file :avatar,
  styles: { thumb: "100x100#" },
  backend: :vips,
  convert_options: { all: "-strip -quality 80" }
```

### ImageMagick-Only Options

The following options only work with ImageMagick. When used with the vips backend, they will be skipped and a warning will be logged:

`-density`, `-depth`, `-gravity`, `-crop`, `-extent`, `-alpha`, `-background`, `-type`, `-posterize`, `-dither`, `-colors`, `-channel`, `-transpose`, `-transverse`, `-normalize`, `-equalize`, `-trim`, `-monochrome`

If you rely heavily on these options, consider keeping those specific attachments on the ImageMagick backend.

## Step 4: Handling Custom Processors

If you have custom processors defined in `lib/paperclip`, they will continue to work even if you switch the primary backend to `:vips`, as long as they are still calling the `convert` or `identify` helper methods.

However, if you want to migrate a custom processor to libvips, you can now use the `vips`, `vips_image` and `vipsheader` helpers:

```ruby
module Paperclip
  class MyVipsProcessor < Processor
    def make
      # Use the new vips helper instead of convert
      vips("thumbnail :src :dst 100",
           src: File.expand_path(file.path),
           dst: File.expand_path(dst.path)
      )
      dst
    end
  end
end
```

## Step 5: Global Migration

Once you have verified that your attachments and processors work correctly with libvips, you can switch the entire application over by updating your global configuration:

```ruby
# config/initializers/paperclip.rb or config/environments/production.rb
config.paperclip_defaults = {
  backend: :vips,
  convert_options: { all: "-strip -quality 85" }
}
```

You can also use per-style backend selection to mix backends within a single attachment:

```ruby
has_attached_file :document,
  styles: {
    # Use vips for large previews (faster)
    preview: { geometry: "800x800>", backend: :vips },
    # Use ImageMagick for thumbnails needing specific options
    thumb: { geometry: "100x100#", backend: :image_magick }
  }
```

## Important Considerations

1.  **Output Parity**: While libvips aims for high quality, its resizing algorithms (Lanczos) may produce slightly different visual results than ImageMagick.
2.  **PDF/SVG Support**: libvips requires additional libraries (like `poppler` or `librsvg`) to process these formats. If you process complex vector formats, ensure the appropriate libraries are installed on your system.
3.  **Exotic Formats**: If you rely on very specific ImageMagick features (like specialized filters or complex layer manipulation), test those attachments thoroughly before switching.
