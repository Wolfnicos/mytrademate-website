/**
 * MyTradeMate Website JavaScript
 * Handles mobile menu, FAQ accordion, and smooth scrolling
 */

// ===================================
// Mobile Menu Toggle
// ===================================
document.addEventListener('DOMContentLoaded', function() {
    const mobileMenuToggle = document.querySelector('.mobile-menu-toggle');
    const navLinks = document.querySelector('.nav-links');

    if (mobileMenuToggle && navLinks) {
        mobileMenuToggle.addEventListener('click', function() {
            navLinks.classList.toggle('active');

            // Animate hamburger icon
            const spans = this.querySelectorAll('span');
            if (navLinks.classList.contains('active')) {
                spans[0].style.transform = 'rotate(45deg) translateY(8px)';
                spans[1].style.opacity = '0';
                spans[2].style.transform = 'rotate(-45deg) translateY(-8px)';
            } else {
                spans[0].style.transform = '';
                spans[1].style.opacity = '';
                spans[2].style.transform = '';
            }
        });

        // Close mobile menu when clicking on a link
        const navLinkItems = navLinks.querySelectorAll('a');
        navLinkItems.forEach(link => {
            link.addEventListener('click', function() {
                navLinks.classList.remove('active');
                const spans = mobileMenuToggle.querySelectorAll('span');
                spans[0].style.transform = '';
                spans[1].style.opacity = '';
                spans[2].style.transform = '';
            });
        });
    }
});

// ===================================
// FAQ Accordion
// ===================================
document.addEventListener('DOMContentLoaded', function() {
    const faqQuestions = document.querySelectorAll('.faq-question');

    faqQuestions.forEach(question => {
        question.addEventListener('click', function() {
            const faqItem = this.parentElement;
            const isActive = faqItem.classList.contains('active');

            // Close all other FAQ items
            document.querySelectorAll('.faq-item').forEach(item => {
                item.classList.remove('active');
            });

            // Toggle current item
            if (!isActive) {
                faqItem.classList.add('active');
            }
        });
    });
});

// ===================================
// Smooth Scroll
// ===================================
document.addEventListener('DOMContentLoaded', function() {
    const links = document.querySelectorAll('a[href^="#"]');

    links.forEach(link => {
        link.addEventListener('click', function(e) {
            const href = this.getAttribute('href');

            // Skip if it's just "#" or empty
            if (href === '#' || href === '') {
                e.preventDefault();
                return;
            }

            const target = document.querySelector(href);

            if (target) {
                e.preventDefault();

                // Get header height for offset
                const header = document.querySelector('.header');
                const headerHeight = header ? header.offsetHeight : 0;

                // Calculate position
                const targetPosition = target.getBoundingClientRect().top + window.pageYOffset - headerHeight - 20;

                // Smooth scroll
                window.scrollTo({
                    top: targetPosition,
                    behavior: 'smooth'
                });
            }
        });
    });
});

// ===================================
// Header Background on Scroll
// ===================================
document.addEventListener('DOMContentLoaded', function() {
    const header = document.querySelector('.header');

    if (header) {
        let lastScrollTop = 0;

        window.addEventListener('scroll', function() {
            const scrollTop = window.pageYOffset || document.documentElement.scrollTop;

            // Add/remove shadow on scroll
            if (scrollTop > 50) {
                header.style.boxShadow = '0 2px 10px rgba(0, 0, 0, 0.3)';
            } else {
                header.style.boxShadow = 'none';
            }

            lastScrollTop = scrollTop;
        });
    }
});

// ===================================
// Fade In Animation on Scroll
// ===================================
document.addEventListener('DOMContentLoaded', function() {
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver(function(entries) {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('fade-in');
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    // Observe feature cards
    const featureCards = document.querySelectorAll('.feature-card');
    featureCards.forEach(card => {
        observer.observe(card);
    });

    // Observe pricing cards
    const pricingCards = document.querySelectorAll('.pricing-card');
    pricingCards.forEach(card => {
        observer.observe(card);
    });

    // Observe FAQ items
    const faqItems = document.querySelectorAll('.faq-item');
    faqItems.forEach(item => {
        observer.observe(item);
    });
});

// ===================================
// Copy Email Address (Optional Enhancement)
// ===================================
document.addEventListener('DOMContentLoaded', function() {
    // Add copy button to email links if needed
    const emailLinks = document.querySelectorAll('a[href^="mailto:"]');

    emailLinks.forEach(link => {
        // Add title attribute for better UX
        if (!link.hasAttribute('title')) {
            link.setAttribute('title', 'Click to send email');
        }
    });
});

// ===================================
// Prevent Default on Empty Hash Links
// ===================================
document.addEventListener('DOMContentLoaded', function() {
    const emptyHashLinks = document.querySelectorAll('a[href="#"]');

    emptyHashLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
        });
    });
});

// ===================================
// Analytics Prevention Verification
// ===================================
// This code block is intentionally empty to demonstrate zero analytics.
// No Google Analytics, no tracking pixels, no telemetry.
// You can verify this by inspecting network traffic.

console.log('%c🔒 MyTradeMate - Privacy First', 'font-size: 16px; font-weight: bold; color: #6366F1;');
console.log('%cNo analytics. No tracking. No data collection.', 'font-size: 12px; color: #94A3B8;');
console.log('%cYour data stays on your device. Period.', 'font-size: 12px; color: #94A3B8;');
