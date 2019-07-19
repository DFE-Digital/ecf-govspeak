module Govspeak
  class PostProcessor
    @extensions = []

    def self.extensions
      @extensions
    end

    def self.process(html, govspeak_document)
      new(html, govspeak_document).output
    end

    def self.extension(title, &block)
      @extensions << [title, block]
    end

    extension("add class to last p of blockquote") do |document|
      document.css("blockquote p:last-child").map do |el|
        el[:class] = "last-child"
      end
    end

    # This "fix" here is tied into the rendering of images as one of the
    # pre-processor tasks. As images can be created inside block level elements
    # it's possible that their block level elements can be HTML entity escaped
    # to produce "valid" HTML.
    #
    # This sucks for us as we spit the user out HTML elements.
    #
    # This fix reverses this, and of course, totally sucks because it's tightly
    # coupled to the `render_image` code and it really isn't cool to undo HTML
    # entity encoding.
    extension("fix image attachment escaping") do |document|
      document.css("figure.image").map do |el|
        xml = el.children.to_s
        next unless xml =~ /&lt;div class="img"&gt;|&lt;figcaption&gt;/

        el.children = xml
          .gsub(
            %r{&lt;(div class="img")&gt;(.*?)&lt;(/div)&gt;},
            "<\\1>\\2<\\3>"
          )
          .gsub(
            %r{&lt;(figcaption)&gt;(.*?)&lt;(/figcaption&)gt;},
            "<\\1>\\2<\\3>"
          )
      end
    end

    extension("embed attachment HTML") do |document|
      document.css("govspeak-embed-attachment").map do |el|
        attachment = govspeak_document.attachments.detect { |a| a[:id] == el["id"] }

        unless attachment
          el.remove
          next
        end

        attachment_html = GovukPublishingComponents.render(
          "govuk_publishing_components/components/attachment",
          attachment: attachment,
          locale: govspeak_document.locale
        )
        el.swap(attachment_html)
      end
    end

    extension("embed attachment link HTML") do |document|
      document.css("govspeak-embed-attachment-link").map do |el|
        attachment = govspeak_document.attachments.detect { |a| a[:id] == el["id"] }

        unless attachment
          el.remove
          next
        end

        attachment_html = GovukPublishingComponents.render(
          "govuk_publishing_components/components/attachment_link",
          attachment: attachment,
          locale: govspeak_document.locale
        )
        el.swap(attachment_html)
      end
    end

    extension("Add table headers and row / column scopes") do |document|
      document.css("thead th").map do |el|
        el.content = el.content.gsub(/^# /, '')
        el.content = el.content.gsub(/[[:space:]]/, '') if el.content.blank? # Removes a strange whitespace in the cell if the cell is already blank.
        el.name = 'td' if el.content.blank? # This prevents a `th` with nothing inside it; a `td` is preferable.
        el[:scope] = "col" if el.content.present? # `scope` shouldn't be used if there's nothing in the table heading.
      end

      document.css(":not(thead) tr td:first-child").map do |el|
        if el.content.match?(/^#($|\s.*$)/)
          el.content = el.content.gsub(/^#($|\s)/, '') # Replace '# ' and '#', but not '#Word'.
          el.name = 'th' if el.content.present? # This also prevents a `th` with nothing inside it; a `td` is preferable.
          el[:scope] = 'row' if el.content.present? # `scope` shouldn't be used if there's nothing in the table heading.
        end
      end
    end

    attr_reader :input, :govspeak_document

    def initialize(html, govspeak_document)
      @input = html
      @govspeak_document = govspeak_document
    end

    def output
      document = nokogiri_document
      self.class.extensions.each do |_, block|
        instance_exec(document, &block)
      end
      document.to_html
    end

  private

    def nokogiri_document
      doc = Nokogiri::HTML::Document.new
      doc.encoding = "UTF-8"
      doc.fragment(input)
    end
  end
end
