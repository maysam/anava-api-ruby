// Main JavaScript for Anava Website

document.addEventListener('DOMContentLoaded', function() {
  // Mobile navigation toggle
  const navToggle = document.querySelector('.nav-toggle');
  const navMenu = document.querySelector('nav ul');
  
  if (navToggle) {
    navToggle.addEventListener('click', function() {
      // Toggle the menu visibility
      navMenu.classList.toggle('show');
      navToggle.classList.toggle('active');
      
      // Toggle between hamburger and X icon
      if (navToggle.innerHTML.trim() === '☰') {
        navToggle.innerHTML = '✕'; // X symbol when menu is open
      } else {
        navToggle.innerHTML = '☰'; // Hamburger symbol when menu is closed
      }
    });
  }
  
  // Smooth scrolling for anchor links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      e.preventDefault();
      
      const targetId = this.getAttribute('href');
      if (targetId === '#') return;
      
      const targetElement = document.querySelector(targetId);
      if (targetElement) {
        window.scrollTo({
          top: targetElement.offsetTop - 80,
          behavior: 'smooth'
        });
        
        // Close mobile menu if open
        if (navMenu.classList.contains('show')) {
          navMenu.classList.remove('show');
          navToggle.classList.remove('active');
        }
      }
    });
  });
  
  // Handle navigation links that point to index.html with anchors
  document.querySelectorAll('a[href^="index.html#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      // Only apply smooth scrolling if we're already on the index page
      if (window.location.pathname.endsWith('index.html') || 
          window.location.pathname.endsWith('/') || 
          window.location.pathname.split('/').pop() === '') {
        e.preventDefault();
        
        const targetId = this.getAttribute('href').split('#')[1];
        const targetElement = document.getElementById(targetId);
        
        if (targetElement) {
          window.scrollTo({
            top: targetElement.offsetTop - 80,
            behavior: 'smooth'
          });
          
          // Close mobile menu if open
          if (navMenu.classList.contains('show')) {
            navMenu.classList.remove('show');
            navToggle.classList.remove('active');
          }
        }
      }
    });
  });
  
  // Form validation for contact form
  const contactForm = document.getElementById('contact-form');
  if (contactForm) {
    contactForm.addEventListener('submit', function(e) {
      e.preventDefault();
      
      const name = document.getElementById('name').value.trim();
      const email = document.getElementById('email').value.trim();
      const subject = document.getElementById('subject').value.trim();
      const message = document.getElementById('message').value.trim();
      let isValid = true;
      
      // Reset previous error messages
      document.querySelectorAll('.error-message').forEach(el => el.remove());
      
      // Validate name
      if (name === '') {
        showError('name', 'Please enter your name');
        isValid = false;
      }
      
      // Validate email
      if (email === '') {
        showError('email', 'Please enter your email');
        isValid = false;
      } else if (!isValidEmail(email)) {
        showError('email', 'Please enter a valid email address');
        isValid = false;
      }
      
      // Validate subject
      if (subject === '') {
        showError('subject', 'Please enter a subject');
        isValid = false;
      }
      
      // Validate message
      if (message === '') {
        showError('message', 'Please enter your message');
        isValid = false;
      }
      
      if (isValid) {
        // Here you would typically send the form data to a server
        // For now, we'll just show a success message
        const formElements = contactForm.elements;
        for (let i = 0; i < formElements.length; i++) {
          if (formElements[i].type !== 'submit') {
            formElements[i].value = '';
          }
        }
        
        const successMessage = document.createElement('div');
        successMessage.className = 'success-message';
        successMessage.textContent = 'Thank you for your message! We will get back to you soon.';
        contactForm.appendChild(successMessage);
        
        // Remove success message after 5 seconds
        setTimeout(() => {
          successMessage.remove();
        }, 5000);
      }
    });
  }
  
  function showError(inputId, message) {
    const input = document.getElementById(inputId);
    const errorMessage = document.createElement('div');
    errorMessage.className = 'error-message';
    errorMessage.textContent = message;
    input.parentNode.appendChild(errorMessage);
    input.classList.add('error');
    
    // Remove error styling when user starts typing
    input.addEventListener('input', function() {
      this.classList.remove('error');
      const error = this.parentNode.querySelector('.error-message');
      if (error) {
        error.remove();
      }
    }, { once: true });
  }
  
  function isValidEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }
  
  // Animate elements when they come into view
  const animateElements = document.querySelectorAll('.animate-on-scroll');
  
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('animated');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1 });
    
    animateElements.forEach(element => {
      observer.observe(element);
    });
  } else {
    // Fallback for browsers that don't support IntersectionObserver
    animateElements.forEach(element => {
      element.classList.add('animated');
    });
  }
});
