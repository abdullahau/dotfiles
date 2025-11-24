# Images

## Image compression

### To target a specific file size

```bash
magick <input.jpeg> -define jpeg:extent=<file size in int or float KB or MB> <output.jpeg>
```
### Relative quality

```bash
magick <input.jpg> -quality <1-100> <output.jpg>
```

## Image Editing

### Black & White / Greyscale

```bash
magick <input.jpeg> -colorspace Gray <output.jpeg>
```
