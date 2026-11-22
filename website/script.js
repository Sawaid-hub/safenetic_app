// ── Navbar scroll effect ──
const nav = document.getElementById('nav');
window.addEventListener('scroll', () => {
    nav.classList.toggle('nav--scrolled', window.scrollY > 50);
});

// ── Mobile menu ──
function toggleMenu() {
    document.getElementById('navLinks').classList.toggle('nav__links--open');
}

function closeMenu() {
    document.getElementById('navLinks').classList.remove('nav__links--open');
}

// ── Scroll reveal (Intersection Observer) ──
const revealObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry, index) => {
        if (entry.isIntersecting) {
            // Stagger the animation for sibling elements
            const siblings = entry.target.parentElement.querySelectorAll('.reveal');
            let delay = 0;
            siblings.forEach((sibling) => {
                if (sibling === entry.target) {
                    entry.target.style.transitionDelay = `${delay}ms`;
                }
                delay += 100;
            });
            entry.target.classList.add('reveal--visible');
        }
    });
}, {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
});

document.querySelectorAll('.reveal').forEach(el => revealObserver.observe(el));

// ── Smooth scroll for anchor links ──
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    });
});

// ── Animated counter for stats ──
function animateCounters() {
    const counters = document.querySelectorAll('.stat__number[data-target]');
    counters.forEach(counter => {
        const target = parseInt(counter.getAttribute('data-target'));
        const duration = 1500;
        const startTime = performance.now();

        function update(currentTime) {
            const elapsed = currentTime - startTime;
            const progress = Math.min(elapsed / duration, 1);
            const eased = 1 - Math.pow(1 - progress, 3);
            counter.textContent = Math.round(target * eased);

            if (progress < 1) {
                requestAnimationFrame(update);
            }
        }
        requestAnimationFrame(update);
    });
}

const statsObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            animateCounters();
            statsObserver.unobserve(entry.target);
        }
    });
}, { threshold: 0.5 });

const statsSection = document.querySelector('.stats');
if (statsSection) {
    statsObserver.observe(statsSection);
}

// ── Parallax effect on phone mockup ──
const phoneMockup = document.querySelector('.phone-mockup');
if (phoneMockup) {
    window.addEventListener('mousemove', (e) => {
        const x = (e.clientX / window.innerWidth - 0.5) * 10;
        const y = (e.clientY / window.innerHeight - 0.5) * 10;
        phoneMockup.style.transform = `perspective(1000px) rotateY(${x}deg) rotateX(${-y}deg)`;
    });
}

// ── Feature Card Modal + 3D Flip ──
const overlay = document.getElementById('cardOverlay');
const featureCards = document.querySelectorAll('.feature-card-container');
let activeCard = null;

function openCard(card) {
    if (activeCard) return;
    activeCard = card;

    const rect = card.getBoundingClientRect();
    const cardCenterX = rect.left + rect.width / 2;
    const cardCenterY = rect.top + rect.height / 2;
    const viewCenterX = window.innerWidth / 2;
    const viewCenterY = window.innerHeight / 2;

    const translateX = viewCenterX - cardCenterX;
    const translateY = viewCenterY - cardCenterY;

    card.style.setProperty('--card-translate', `translate(${translateX}px, ${translateY}px)`);

    overlay.classList.add('active');
    card.classList.add('active');
    document.body.classList.add('card-modal-open');

    // Flip after centering animation
    setTimeout(() => {
        card.classList.add('flipped');
    }, 300);
}

function closeCard() {
    if (!activeCard) return;
    const card = activeCard;

    card.classList.remove('flipped');

    // Wait for flip to finish, then move back
    setTimeout(() => {
        card.classList.remove('active');
        overlay.classList.remove('active');
        document.body.classList.remove('card-modal-open');
        activeCard = null;
    }, 500);
}

featureCards.forEach(card => {
    card.addEventListener('click', (e) => {
        if (activeCard === card) {
            closeCard();
        } else if (!activeCard) {
            openCard(card);
        }
    });
});

overlay.addEventListener('click', closeCard);

// Close on Escape key
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && activeCard) {
        closeCard();
    }
});
