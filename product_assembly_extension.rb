# Uncomment this if you reference any of your controllers in activate
# require_dependency 'application'

class ProductAssemblyExtension < Spree::Extension
  version "1.0"
  description "Describe your extension here"
  url "http://yourwebsite.com/product_assembly"

  # Please use product_assembly/config/routes.rb instead for extension routes.

  def self.require_gems(config)
    #config.gem 'composite_primary_keys', :lib => false
  end
  
  def activate

    Admin::ProductsController.class_eval do
      before_filter :add_parts_tab
      private
      def add_parts_tab
        @product_admin_tabs << { :name => "Parts", :url => "admin_product_parts_url" }
      end
    end
    
    Product.class_eval do

      has_and_belongs_to_many  :assemblies, :class_name => "Product",
            :join_table => "assemblies_parts",
            :foreign_key => "part_id", :association_foreign_key => "assembly_id"

      has_and_belongs_to_many  :parts, :class_name => "Variant",
            :join_table => "assemblies_parts",
            :foreign_key => "assembly_id", :association_foreign_key => "part_id"


      alias_method :orig_on_hand, :on_hand
      # returns the number of inventory units "on_hand" for this product
      def on_hand
        if self.assembly?
          parts.map{|v| v.on_hand / self.count_of(v) }.min
        else
          orig_on_hand
        end
      end

      alias_method :orig_on_hand=, :on_hand=
      def on_hand=(new_level)
        orig_on_hand=(new_level) unless self.assembly?
      end

      alias_method :orig_has_stock?, :has_stock?
      def has_stock?
        if self.assembly?
          !parts.detect{|v| self.count_of(v) > v.on_hand}
        else
          orig_has_stock?
        end
      end

      def add_part(variant, count = 1)
        begin
          ap = AssembliesPart.get(self.id, variant.id)        
          ap.count += count
          ap.save
        rescue
          self.parts << variant
          set_part_count(variant, count) if count > 1
        end        
      end
      
      def remove_part(variant)
        begin
          ap = AssembliesPart.get(self.id, variant.id)        
          ap.count -= 1
          if ap.count > 0
            ap.save
          else
            ap.destroy
          end
        rescue
        end        
      end
      
      def set_part_count(variant, count)
        begin
          ap = AssembliesPart.get(self.id, variant.id)
          if count > 0        
            ap.count = count
            ap.save
          else
            ap.destroy  
          end
        rescue
        end         
      end

      def assembly?
        parts.present?
      end
      
      def part?
        assemblies.present?
      end
      
      def count_of(variant)
        begin
          ap = AssembliesPart.get(self.id, variant.id)        
          ap.count
        rescue
          0
        end         
      end

    end
    
    
    InventoryUnit.class_eval do
      def self.sell_units(order)
        order.line_items.each do |line_item|
          variant = line_item.variant
          quantity = line_item.quantity

          product = variant.product
          if product.assembly?
            product.parts.each do |v|
              on_hand_units = self.retrieve_on_hand(v, quantity * product.count_of(v))
              mark_units_as_selled(order, on_hand_units)
            end
          else
            on_hand_units = self.retrieve_on_hand(variant, quantity)
            mark_units_as_selled(order, on_hand_units)
          end
        end
      end
      
      private
      
      def self.mark_units_as_selled(order, units)       
        # mark all of these units as sold and associate them with this order 
        units.each do |unit|          
          unit.order = order
          unit.sell!
        end
        # right now we always allow back ordering
        backorder = quantity - units.size
        backorder.times do 
          order.inventory_units.create(:variant => variant, :state => "backordered")
        end      
      end
    end

  end
end