# Как добавить твоё фото как hero-экран

## Вариант 1: Быстрый способ (рекомендуется)

1. Сохрани фото в папке с сайтом под именем `hero-bg.jpg`
2. Изменим CSS в `mihaly-shop.html`, найди строку:

```html
<section class="hero">
```

3. Замени на:

```html
<section class="hero" style="background-image: linear-gradient(135deg, rgba(0, 0, 0, 0.4) 0%, rgba(0, 0, 0, 0.25) 100%), url('hero-bg.jpg');">
```

## Вариант 2: Через inline CSS в файл

Отредактируй файл и найди секцию `.hero` в `<style>`, добавь путь к изображению:

```css
.hero {
    background: linear-gradient(135deg, rgba(0, 0, 0, 0.4) 0%, rgba(0, 0, 0, 0.25) 100%);
    background-image: 
        linear-gradient(135deg, rgba(0, 0, 0, 0.4) 0%, rgba(0, 0, 0, 0.25) 100%),
        url('./hero-bg.jpg');  /* ← Путь к твоему фото */
    background-size: cover;
    background-position: center;
    background-attachment: fixed;
}
```

## Вариант 3: Используя внешний URL

Если фото уже в интернете, просто вставь URL:

```css
.hero {
    background-image: 
        linear-gradient(135deg, rgba(0, 0, 0, 0.4) 0%, rgba(0, 0, 0, 0.25) 100%),
        url('https://example.com/твое-фото.jpg');
    /* ... остальное ... */
}
```

## Результат

После этого твоё фото будет:
- На весь экран (100vh)
- С красивой полупрозрачной тёмной маской (для читаемости текста)
- Фиксированным при скролле (parallax эффект)
- Адаптивным под все экраны

## Совет

Фото должно быть:
- **Минимум 1920×1080px** для качества
- **Не более 500KB** для скорости загрузки
- В формате **JPG** или **PNG**
- С **хорошим контрастом** — текст должен читаться поверх фото
